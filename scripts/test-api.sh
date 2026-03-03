#!/bin/bash
# Test API endpoints

set -e

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
    echo "Error: No API key found. Run deploy.sh first."
    exit 1
fi

passed=0
failed=0

test_endpoint() {
    local name="$1" method="$2" endpoint="$3" data="$4" expected="$5" auth="${6:-true}"
    
    local url="$API_HOST$endpoint"
    [ "$auth" = "true" ] && url="$url?key=$API_KEY"
    
    local opts="-s -w \n%{http_code}"
    [ -n "$data" ] && opts="$opts -X $method -H Content-Type:application/json -d $data" || opts="$opts -X $method"
    
    local response=$(curl $opts "$url")
    local code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$code" = "$expected" ]; then
        echo "✓ $name"
        ((passed++))
    else
        echo "✗ $name (expected $expected, got $code)"
        echo "  $body"
        ((failed++))
    fi
}

echo "Testing: $API_HOST"
echo ""

# System endpoints
echo "--- System ---"
test_endpoint "Health check" GET "/api/v1/health" "" 200 false
test_endpoint "Version" GET "/api/v1/version" "" 200 false

# User CRUD
echo ""
echo "--- Users ---"
test_endpoint "Create user" POST "/api/v1/users" '{"name":"Alice","email":"alice@test.com"}' 201
test_endpoint "Create user 2" POST "/api/v1/users" '{"name":"Bob","email":"bob@test.com"}' 201
test_endpoint "List users" GET "/api/v1/users" "" 200
test_endpoint "Get user" GET "/api/v1/users/1" "" 200
test_endpoint "Update user" PUT "/api/v1/users/1" '{"name":"Alice Updated"}' 200
test_endpoint "Delete user" DELETE "/api/v1/users/2" "" 200

# Error cases
echo ""
echo "--- Errors ---"
test_endpoint "Not found" GET "/api/v1/users/999" "" 404
test_endpoint "Missing fields" POST "/api/v1/users" '{"name":"Incomplete"}' 400
test_endpoint "Duplicate email" POST "/api/v1/users" '{"name":"Clone","email":"alice@test.com"}' 409

# Device registration
echo ""
echo "--- Devices ---"
test_endpoint "Register device" POST "/api/v1/devices/register" '{"user_id":"1","device_type":"ios","push_token":"token123"}' 200
test_endpoint "Unregister device" POST "/api/v1/devices/unregister" '{"user_id":"1"}' 200

echo ""
echo "Results: $passed passed, $failed failed"
