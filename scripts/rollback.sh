#!/usr/bin/env bash
#
# Roll back to the previously running image.
# Usage: ./rollback.sh <dev|uat|prod> <previous-image:tag>
#
set -euo pipefail

ENVIRONMENT="${1:?Usage: rollback.sh <env> <previous-image>}"
PREVIOUS_IMAGE="${2:?Usage: rollback.sh <env> <previous-image>}"

ENV_FILE="env/${ENVIRONMENT}.env"
LOG_FILE="/var/log/deploy-${ENVIRONMENT}.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ROLLBACK: $*" | tee -a "$LOG_FILE"; }

if [[ "$PREVIOUS_IMAGE" == "none" || -z "$PREVIOUS_IMAGE" ]]; then
    log "No previous image recorded — nothing to roll back to."
    log "Manual intervention required."
    exit 1
fi

log "Rolling $ENVIRONMENT back to $PREVIOUS_IMAGE"

export APP_IMAGE="$PREVIOUS_IMAGE"
export ENV_FILE="$ENV_FILE"

docker compose --env-file "$ENV_FILE" up -d --no-deps app

log "Verifying rolled-back container"
for i in {1..18}; do
    status=$(docker inspect --format='{{.State.Health.Status}}' payment-api 2>/dev/null || echo starting)
    if [[ "$status" == "healthy" ]]; then
        log "Rollback successful — running $PREVIOUS_IMAGE"
        exit 0
    fi
    sleep 10
done

log "ERROR: rollback did not reach a healthy state. Escalate."
exit 1
