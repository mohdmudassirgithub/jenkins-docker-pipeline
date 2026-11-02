#!/usr/bin/env bash
#
# Deploy an image to a target environment.
# Usage: ./deploy.sh <dev|uat|prod> <image:tag>
#
set -euo pipefail

ENVIRONMENT="${1:?Usage: deploy.sh <env> <image:tag>}"
IMAGE="${2:?Usage: deploy.sh <env> <image:tag>}"

ENV_FILE="env/${ENVIRONMENT}.env"
LOG_FILE="/var/log/deploy-${ENVIRONMENT}.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

if [[ ! -f "$ENV_FILE" ]]; then
    log "ERROR: $ENV_FILE not found"
    exit 1
fi

log "Deploying $IMAGE to $ENVIRONMENT"

export APP_IMAGE="$IMAGE"
export ENV_FILE="$ENV_FILE"

log "Pulling image"
docker compose --env-file "$ENV_FILE" pull app

log "Recreating services"
docker compose --env-file "$ENV_FILE" up -d --no-deps app

log "Waiting for the container to report healthy"
for i in {1..30}; do
    status=$(docker inspect --format='{{.State.Health.Status}}' payment-api 2>/dev/null || echo starting)
    if [[ "$status" == "healthy" ]]; then
        log "Container healthy after ${i}0s"
        exit 0
    fi
    sleep 10
done

log "ERROR: container did not become healthy within 300s"
docker compose logs --tail=50 app | tee -a "$LOG_FILE"
exit 1
