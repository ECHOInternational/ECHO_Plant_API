#!/usr/bin/env bash
# =============================================================================
# publication-gate.sh: the safety gate of ops-publication.yml (FPI plan API-15).
#
# Reads the workflow inputs from the environment (never interpolated into the
# script, so an input cannot inject shell):
#   TASK  APPLY  CONFIRM_APPLY  EXPECTED_DIGEST  WAVE_KEY  SELECTOR  IDS  LIMIT
#   RULE
# Writes allowed=true or allowed=false to $GITHUB_OUTPUT (when set) and exits
# 0 only when the run may go ahead. The run-task job runs only on
# allowed == 'true'. spec/workflows/ops_publication_gate_spec.rb runs this
# script with good and bad inputs.
#
# Rules:
#   - TASK is report, set_rule, publish_wave or unpublish_wave
#   - APPLY=true needs CONFIRM_APPLY to be exactly PUBLISH-WAVE-APPLY
#   - publish_wave with APPLY=true needs EXPECTED_DIGEST (64 hex characters,
#     copied from the dry run)
#   - report is read-only: APPLY=true is refused
#   - publish_wave and unpublish_wave need a wave key; set_rule needs RULE
# =============================================================================

set -uo pipefail

problems=()
refuse() { problems+=("$1"); }

TASK=${TASK:-}
APPLY=${APPLY:-false}

case "$TASK" in
  report|set_rule|publish_wave|unpublish_wave) ;;
  *) refuse "unknown task '${TASK}'" ;;
esac

case "$APPLY" in
  true|false) ;;
  *) refuse "apply must be true or false" ;;
esac

if [ "$APPLY" = "true" ]; then
  [ "${CONFIRM_APPLY:-}" = "PUBLISH-WAVE-APPLY" ] ||
    refuse "apply=true requires confirm_apply to be exactly PUBLISH-WAVE-APPLY"
  [ "$TASK" = "report" ] && refuse "report is read-only; leave apply false"
  if [ "$TASK" = "publish_wave" ] && ! [[ "${EXPECTED_DIGEST:-}" =~ ^[0-9a-f]{64}$ ]]; then
    refuse "publish_wave with apply=true requires expected_digest (64 hex characters from the dry run)"
  fi
fi

if [ "$TASK" = "publish_wave" ] || [ "$TASK" = "unpublish_wave" ]; then
  [[ "${WAVE_KEY:-}" =~ ^[a-z0-9-]{3,40}$ ]] || refuse "${TASK} requires wave_key (3-40 of a-z, 0-9 and '-')"
fi

if [ "$TASK" = "publish_wave" ]; then
  case "${SELECTOR:-quality}" in
    quality|remaining|ids) ;;
    *) refuse "selector must be quality, remaining or ids" ;;
  esac
  [ "${SELECTOR:-quality}" = "ids" ] && [ -z "${IDS:-}" ] && refuse "selector ids requires ids"
  [[ "${IDS:-}" =~ ^[0-9a-fA-F,-]*$ ]] || refuse "ids must be comma-separated plant UUIDs"
  [[ "${LIMIT:-}" =~ ^[0-9]*$ ]] || refuse "limit must be a whole number"
fi

[ "$TASK" = "set_rule" ] && [ -z "${RULE:-}" ] && refuse "set_rule requires rule (JSON)"

if [ ${#problems[@]} -eq 0 ]; then
  echo "Safety gate passed: task=${TASK} apply=${APPLY}."
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "allowed=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

for p in "${problems[@]}"; do
  echo "::error::SAFETY GATE: ${p}"
done
[ -n "${GITHUB_OUTPUT:-}" ] && echo "allowed=false" >> "$GITHUB_OUTPUT"
exit 1
