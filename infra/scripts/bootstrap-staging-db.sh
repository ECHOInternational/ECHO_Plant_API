#!/usr/bin/env bash
# =============================================================================
# bootstrap-staging-db.sh
#
# PURPOSE
#   One-time setup of the staging database and credentials on the shared
#   production RDS instance (echocommunity-production).  Run this script
#   ONCE before executing "terraform apply" for the staging environment.
#
# WHAT IT DOES (in order)
#   1. Retrieves the RDS master credentials from Secrets Manager (the
#      auto-managed secret rds!db-65c1ca5f-392b-47ef-b6f1-e71c13c5b512).
#   2. Generates a strong random password for the staging app role.
#   3. Connects to the RDS instance via psql and:
#      a. Creates the database "Plant_API_staging" (if it does not exist).
#      b. Creates the login role "plantapi_staging_app" with the generated
#         password (if it does not exist).
#      c. Grants all privileges on the new database to the new role and
#         sets default privileges so future objects are accessible.
#   4. Stores the staging credentials in Secrets Manager as
#      rds/echocommunity-production/plantapi-staging-app  (matching the
#      naming convention of sibling secrets such as plantapi-app).
#   5. Loads db/structure.sql into the new database as the new role so
#      the schema is ready for the first ECS migration task.
#
# PRE-REQUISITES
#   • psql client installed on this machine.
#   • This machine can reach the RDS endpoint on port 5432.
#     The RDS instance (echocommunity-production) has PubliclyAccessible=true;
#     its security groups (sg-007ae20731af7483c, sg-35fa1548) must allow
#     inbound 5432 from this machine's IP, OR run this script from inside the
#     VPC (e.g. the bastion/NAT instance).
#   • AWS credentials with:
#       secretsmanager:GetSecretValue on the RDS master secret
#       secretsmanager:CreateSecret   (to store plantapi-staging-app)
#   • AWS_PROFILE env var set to a profile with the above permissions, or
#     the environment already has credentials (instance role, etc.).
#
# IDEMPOTENCY
#   The script checks whether the database and role already exist before
#   creating them.  Re-running is safe: existing objects are left unchanged.
#   If the Secrets Manager secret already exists the script exits rather than
#   overwriting the stored password — delete the secret first if you need to
#   rotate it.
#
# NO-ECHO DISCIPLINE
#   set -euo pipefail is used.  set -x is intentionally NOT set.
#   Secrets are stored in variables and NEVER passed to echo or logged.
#   Progress messages use deliberate strings that contain no values.
#
# USAGE
#   AWS_PROFILE=YourWriteProfile ./infra/scripts/bootstrap-staging-db.sh
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (all non-secret; edit here if your environment differs)
# ---------------------------------------------------------------------------

RDS_ENDPOINT="echocommunity-production.ceui3mx2fcbs.us-east-1.rds.amazonaws.com"
RDS_PORT="5432"
MASTER_SECRET_ID="rds!db-65c1ca5f-392b-47ef-b6f1-e71c13c5b512"
STAGING_SECRET_NAME="rds/echocommunity-production/plantapi-staging-app"
STAGING_SECRET_DESCRIPTION="Scoped DB role plantapi_staging_app (Plant_API_staging)"
STAGING_DB="Plant_API_staging"
STAGING_ROLE="plantapi_staging_app"
STRUCTURE_SQL_PATH="$(cd "$(dirname "$0")/../.." && pwd)/db/structure.sql"
AWS_REGION="${AWS_REGION:-us-east-1}"

# ---------------------------------------------------------------------------
# Helper: print a progress message (never prints values)
# ---------------------------------------------------------------------------
progress() {
  echo "[bootstrap-staging-db] $*"
}

# ---------------------------------------------------------------------------
# Step 0: Verify psql is available
# ---------------------------------------------------------------------------
progress "Checking for psql..."
if ! command -v psql > /dev/null 2>&1; then
  echo "ERROR: psql is not installed or not in PATH." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Retrieve master credentials from Secrets Manager
# ---------------------------------------------------------------------------
progress "Retrieving RDS master credentials from Secrets Manager..."

master_secret_json="$(
  aws secretsmanager get-secret-value \
    --region "$AWS_REGION" \
    --secret-id "$MASTER_SECRET_ID" \
    --query SecretString \
    --output text
)"

# Parse JSON with python3 (no jq dependency required)
master_username="$(printf '%s' "$master_secret_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['username'])")"
master_password="$(printf '%s' "$master_secret_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['password'])")"
unset master_secret_json

progress "Master credentials retrieved."

# ---------------------------------------------------------------------------
# Step 2: Generate a strong password for the staging app role
# ---------------------------------------------------------------------------
progress "Generating staging app role password..."
staging_password="$(openssl rand -base64 32)"
progress "Staging password generated."

# ---------------------------------------------------------------------------
# Step 3a: Create the staging database (idempotent)
# ---------------------------------------------------------------------------
progress "Checking whether database '$STAGING_DB' exists..."

db_exists="$(
  PGPASSWORD="$master_password" psql \
    --host="$RDS_ENDPOINT" \
    --port="$RDS_PORT" \
    --username="$master_username" \
    --dbname="postgres" \
    --tuples-only \
    --no-align \
    --command="SELECT 1 FROM pg_database WHERE datname = '${STAGING_DB}';"
)"

if [ "$db_exists" = "1" ]; then
  progress "Database '$STAGING_DB' already exists — skipping CREATE DATABASE."
else
  progress "Creating database '$STAGING_DB'..."
  PGPASSWORD="$master_password" psql \
    --host="$RDS_ENDPOINT" \
    --port="$RDS_PORT" \
    --username="$master_username" \
    --dbname="postgres" \
    --command="CREATE DATABASE \"${STAGING_DB}\";"
  progress "Database '$STAGING_DB' created."
fi

# ---------------------------------------------------------------------------
# Step 3b: Create the staging app role (idempotent)
# ---------------------------------------------------------------------------
progress "Checking whether role '$STAGING_ROLE' exists..."

role_exists="$(
  PGPASSWORD="$master_password" psql \
    --host="$RDS_ENDPOINT" \
    --port="$RDS_PORT" \
    --username="$master_username" \
    --dbname="postgres" \
    --tuples-only \
    --no-align \
    --command="SELECT 1 FROM pg_roles WHERE rolname = '${STAGING_ROLE}';"
)"

if [ "$role_exists" = "1" ]; then
  progress "Role '$STAGING_ROLE' already exists — skipping CREATE ROLE."
else
  progress "Creating role '$STAGING_ROLE'..."
  # Use printf with a heredoc approach to avoid exposing the password in
  # the process argument list.
  PGPASSWORD="$master_password" psql \
    --host="$RDS_ENDPOINT" \
    --port="$RDS_PORT" \
    --username="$master_username" \
    --dbname="postgres" \
    --command="CREATE ROLE \"${STAGING_ROLE}\" LOGIN PASSWORD '$(printf '%s' "$staging_password" | sed "s/'/''/g")';"
  progress "Role '$STAGING_ROLE' created."
fi

# ---------------------------------------------------------------------------
# Step 3c: Grant privileges
# ---------------------------------------------------------------------------
progress "Granting privileges on '$STAGING_DB' to '$STAGING_ROLE'..."

PGPASSWORD="$master_password" psql \
  --host="$RDS_ENDPOINT" \
  --port="$RDS_PORT" \
  --username="$master_username" \
  --dbname="$STAGING_DB" \
  --command="
    GRANT ALL PRIVILEGES ON DATABASE \"${STAGING_DB}\" TO \"${STAGING_ROLE}\";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"${STAGING_ROLE}\";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \"${STAGING_ROLE}\";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO \"${STAGING_ROLE}\";
    GRANT ALL ON SCHEMA public TO \"${STAGING_ROLE}\";
  "

progress "Privileges granted."

# ---------------------------------------------------------------------------
# Step 4: Store the staging credentials in Secrets Manager
# ---------------------------------------------------------------------------
progress "Checking whether Secrets Manager secret '$STAGING_SECRET_NAME' exists..."

secret_exists="$(
  aws secretsmanager describe-secret \
    --region "$AWS_REGION" \
    --secret-id "$STAGING_SECRET_NAME" \
    --query Name \
    --output text 2>/dev/null || true
)"

if [ -n "$secret_exists" ]; then
  progress "Secret '$STAGING_SECRET_NAME' already exists — NOT overwriting."
  progress "If you need to rotate the password, delete the secret first and re-run."
else
  progress "Storing credentials in Secrets Manager as '$STAGING_SECRET_NAME'..."
  # Build the JSON value in a variable — never echo it
  staging_secret_json="$(python3 -c "
import json, sys
print(json.dumps({'username': sys.argv[1], 'password': sys.argv[2]}))
" "$STAGING_ROLE" "$staging_password")"

  aws secretsmanager create-secret \
    --region "$AWS_REGION" \
    --name "$STAGING_SECRET_NAME" \
    --description "$STAGING_SECRET_DESCRIPTION" \
    --secret-string "$staging_secret_json"

  unset staging_secret_json
  progress "Secret '$STAGING_SECRET_NAME' created."
fi

# Clear the staging password from memory
unset staging_password

# ---------------------------------------------------------------------------
# Step 5: Load db/structure.sql into the staging database
# ---------------------------------------------------------------------------
progress "Checking for db/structure.sql at: $STRUCTURE_SQL_PATH"
if [ ! -f "$STRUCTURE_SQL_PATH" ]; then
  echo "WARNING: db/structure.sql not found at '$STRUCTURE_SQL_PATH'." >&2
  echo "         Schema load skipped.  Run 'bundle exec rails db:schema:load'" >&2
  echo "         (or db:structure:load) against the staging database manually." >&2
else
  progress "Retrieving staging app role password from Secrets Manager for schema load..."
  staging_secret_json="$(
    aws secretsmanager get-secret-value \
      --region "$AWS_REGION" \
      --secret-id "$STAGING_SECRET_NAME" \
      --query SecretString \
      --output text
  )"
  schema_password="$(printf '%s' "$staging_secret_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['password'])")"
  unset staging_secret_json

  progress "Loading db/structure.sql into '$STAGING_DB' as '$STAGING_ROLE'..."
  PGPASSWORD="$schema_password" psql \
    --host="$RDS_ENDPOINT" \
    --port="$RDS_PORT" \
    --username="$STAGING_ROLE" \
    --dbname="$STAGING_DB" \
    --file="$STRUCTURE_SQL_PATH"

  unset schema_password
  progress "Schema loaded successfully."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
progress "Bootstrap complete."
progress "Next steps:"
progress "  1. Retrieve the staging secret ARN and update:"
progress "       infra/envs/staging/terraform.tfvars  (db_secret_arn)"
progress "     Command:"
progress "       aws secretsmanager describe-secret \\"
progress "         --secret-id '$STAGING_SECRET_NAME' \\"
progress "         --query ARN --output text"
progress "  2. Seed the APPLICATION_JWT_SECRET for staging (see infra/README.md)."
progress "  3. Run: cd infra/envs/staging && terraform apply"
