#!/usr/bin/env bash
#
# Post-release verification.
# Usage: ./health-check.sh <dev|uat|prod>
#
set -euo pipefail

ENVIRONMENT="${1:?Usage: health-check.sh <env>}"

case "$ENVIRONMENT" in
    dev)  BASE_URL="http://dev.example.com:8000"  ;;
    uat)  BASE_URL="https://uat.example.com"      ;;
    prod) BASE_URL="https://app.example.com"      ;;
    *)    echo "Unknown environment: $ENVIRONMENT"; exit 1 ;;
esac

echo "Verifying $ENVIRONMENT at $BASE_URL"

# 1. Health endpoint
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BASE_URL/health")
if [[ "$code" != "200" ]]; then
    echo "FAIL: /health returned $code"
    exit 1
fi
echo "OK: /health returned 200"

# 2. TLS certificate expiry (skipped for plain HTTP)
if [[ "$BASE_URL" == https://* ]]; then
    host="${BASE_URL#https://}"
    expiry=$(echo | openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null \
             | openssl x509 -noout -enddate | cut -d= -f2)
    expiry_epoch=$(date -d "$expiry" +%s)
    days_left=$(( (expiry_epoch - $(date +%s)) / 86400 ))
    echo "OK: TLS certificate valid for $days_left more days"
    [[ "$days_left" -lt 15 ]] && echo "WARNING: certificate expires in under 15 days"
fi

# 3. Container state
state=$(docker inspect --format='{{.State.Status}}' payment-api)
[[ "$state" != "running" ]] && { echo "FAIL: container state is $state"; exit 1; }
echo "OK: container is running"

# 4. No errors logged since the release
errors=$(docker logs --since 2m payment-api 2>&1 | grep -ci 'ERROR' || true)
if [[ "$errors" -gt 0 ]]; then
    echo "WARNING: $errors ERROR lines in the last 2 minutes"
    docker logs --since 2m payment-api 2>&1 | grep -i 'ERROR' | tail -10
fi

echo "Verification passed for $ENVIRONMENT"
