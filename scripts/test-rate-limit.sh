#!/bin/bash
# Test rate limiting by sending rapid requests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo "Error: No project set"
    exit 1
fi

API_HOST="https://$PROJECT_ID.appspot.com"

# Get API key
if [ -f "$PROJECT_ROOT/.api_key" ]; then
    API_KEY=$(cat "$PROJECT_ROOT/.api_key")
else
    KEY_NAME=$(gcloud services api-keys list --format="value(name)" 2>/dev/null | head -1)
    [ -n "$KEY_NAME" ] && API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" --format="value(keyString)" 2>/dev/null)
fi

if [ -z "$API_KEY" ]; then
    echo "Error: No API key found"
    exit 1
fi

NUM_REQUESTS="${1:-150}"

echo "Sending $NUM_REQUESTS requests to test rate limiting..."
echo "Rate limit: 1000 reads/min, 100 writes/min"
echo ""

success=0
limited=0
errors=0

for i in $(seq 1 $NUM_REQUESTS); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$API_HOST/api/v1/users?key=$API_KEY")
    case $code in
        200) ((success++)) ;;
        429) ((limited++)) ;;
        *) ((errors++)) ;;
    esac
    printf "\rProgress: %d/%d (429s: %d)" $i $NUM_REQUESTS $limited
done

echo ""
echo ""
echo "Results:"
echo "  Success: $success"
echo "  Rate limited (429): $limited"
echo "  Errors: $errors"

[ $limited -gt 0 ] && echo "Rate limiting is working!"
