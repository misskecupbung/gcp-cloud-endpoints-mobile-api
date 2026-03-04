#!/bin/bash
# Test rate limiting by sending rapid parallel requests

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
API_HOST="https://$PROJECT_ID.appspot.com"

# Get API key
KEY_NAME=$(gcloud services api-keys list --format="value(name)" 2>/dev/null | head -1)
API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" --format="value(keyString)" 2>/dev/null)

if [ -z "$API_KEY" ]; then
    echo "Error: No API key found"
    exit 1
fi

NUM_REQUESTS="${1:-150}"

echo "Sending $NUM_REQUESTS parallel requests to test rate limiting..."
echo "Rate limit: 100 reads/min"
echo ""

# Send requests in parallel using xargs
seq 1 $NUM_REQUESTS | xargs -P 50 -I {} curl -s -o /dev/null -w "%{http_code}\n" "$API_HOST/api/v1/users?key=$API_KEY" > /tmp/rate_limit_results.txt

success=$(grep -c "200" /tmp/rate_limit_results.txt || echo 0)
limited=$(grep -c "429" /tmp/rate_limit_results.txt || echo 0)
errors=$(grep -cvE "200|429" /tmp/rate_limit_results.txt || echo 0)

echo "Results:"
echo "  Success (200): $success"
echo "  Rate limited (429): $limited"
echo "  Errors: $errors"

rm -f /tmp/rate_limit_results.txt
