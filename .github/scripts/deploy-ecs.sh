#!/usr/bin/env bash
# =============================================================================
# deploy-ecs.sh CLUSTER SERVICE MIGRATE_FAMILY IMAGE [SMOKE_URL]
#
# Deploys IMAGE to an ECS environment in the order that keeps old tasks
# healthy throughout:
#   1. Register new revisions of the web + migrate task definitions with IMAGE.
#   2. Run the migrate task once (network config borrowed from the service);
#      abort unless it exits 0.
#   3. Point the service at the new web revision and wait for stability.
#   4. Verify the stable deployment is actually the new revision (the
#      deployment circuit breaker rolls back on failure, which also reports
#      "stable" — that must fail the pipeline, not pass it).
#   5. Optionally smoke-test SMOKE_URL (/health + a GraphQL read).
# =============================================================================

set -euo pipefail

CLUSTER=$1
SERVICE=$2
MIGRATE_FAMILY=$3
IMAGE=$4
SMOKE_URL=${5:-}

# --- 1. Register new task definition revisions -------------------------------

register_revision() {
  local family=$1
  aws ecs describe-task-definition --task-definition "$family" \
    --query 'taskDefinition' --output json |
    jq --arg IMAGE "$IMAGE" '
      .containerDefinitions[0].image = $IMAGE
      | del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
            .compatibilities, .registeredAt, .registeredBy)' |
    aws ecs register-task-definition --cli-input-json file:///dev/stdin \
      --query 'taskDefinition.taskDefinitionArn' --output text
}

WEB_FAMILY=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].taskDefinition' --output text | sed 's|.*task-definition/||; s|:.*||')

WEB_TD=$(register_revision "$WEB_FAMILY")
MIGRATE_TD=$(register_revision "$MIGRATE_FAMILY")
echo "Registered: $WEB_TD"
echo "Registered: $MIGRATE_TD"

# --- 2. Run migrations --------------------------------------------------------

NETCONF=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].networkConfiguration' --output json)

TASK_ARN=$(aws ecs run-task \
  --cluster "$CLUSTER" \
  --task-definition "$MIGRATE_TD" \
  --launch-type FARGATE \
  --network-configuration "$NETCONF" \
  --query 'tasks[0].taskArn' --output text)
echo "Migration task: $TASK_ARN"

aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN"

EXIT_CODE=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].exitCode' --output text)
if [ "$EXIT_CODE" != "0" ]; then
  echo "::error::Migration task exited with code $EXIT_CODE — aborting deploy."
  aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
    --query 'tasks[0].{stoppedReason:stoppedReason,container:containers[0].reason}' --output json
  exit 1
fi
echo "Migrations OK."

# --- 3. Deploy the web service ------------------------------------------------

aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" \
  --task-definition "$WEB_TD" --query 'service.serviceName' --output text
echo "Waiting for service stability (circuit breaker auto-rolls-back on failure)..."
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"

# --- 4. Confirm we are stable on the NEW revision ------------------------------

ACTIVE_TD=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].deployments[0].taskDefinition' --output text)
if [ "$ACTIVE_TD" != "$WEB_TD" ]; then
  echo "::error::Service stabilised on $ACTIVE_TD instead of $WEB_TD — the circuit breaker rolled the deployment back."
  exit 1
fi
echo "Service running $WEB_TD."

# --- 5. Smoke test -------------------------------------------------------------

if [ -n "$SMOKE_URL" ]; then
  echo "Smoke-testing $SMOKE_URL ..."
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$SMOKE_URL/health")
  if [ "$STATUS" != "200" ]; then
    echo "::error::/health returned $STATUS"
    exit 1
  fi
  BODY=$(curl -s --max-time 10 -X POST "$SMOKE_URL/graphql" \
    -H 'Content-Type: application/json' \
    -d '{"query":"{ plants(first: 1) { totalCount } }"}')
  echo "$BODY" | jq -e '.data.plants.totalCount >= 0' > /dev/null || {
    echo "::error::GraphQL smoke query failed: $BODY"
    exit 1
  }
  echo "Smoke tests passed."
fi
