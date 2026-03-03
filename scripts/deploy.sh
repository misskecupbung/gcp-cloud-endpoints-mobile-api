#!/bin/bash
# Deploy Flask API to App Engine with Cloud Endpoints

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_ROOT/app"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo "Error: No project set. Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo "Deploying to: $PROJECT_ID"

# Create app.yaml from template
cp "$APP_DIR/app.yaml.template" "$APP_DIR/app.yaml"

# Update openapi.yaml if needed
if grep -q "YOUR_PROJECT_ID" "$PROJECT_ROOT/openapi.yaml"; then
    sed -i.bak "s/YOUR_PROJECT_ID/$PROJECT_ID/g" "$PROJECT_ROOT/openapi.yaml"
    rm -f "$PROJECT_ROOT/openapi.yaml.bak"
fi

# Deploy Cloud Endpoints config
echo "Deploying Cloud Endpoints configuration..."
gcloud endpoints services deploy "$PROJECT_ROOT/openapi.yaml" --quiet

# Deploy to App Engine
echo "Deploying to App Engine..."
cd "$APP_DIR"
gcloud app deploy app.yaml --quiet

# Create API key if it doesn't exist
KEY_NAME=$(gcloud services api-keys list \
    --filter="displayName:mobile-api-key" \
    --format="value(name)" 2>/dev/null || true)

if [ -z "$KEY_NAME" ]; then
    echo "Creating API key..."
    gcloud services api-keys create \
        --display-name="mobile-api-key" \
        --api-target="service=$PROJECT_ID.appspot.com" \
        --quiet 2>/dev/null || true
    sleep 3
    KEY_NAME=$(gcloud services api-keys list \
        --filter="displayName:mobile-api-key" \
        --format="value(name)" 2>/dev/null | head -1)
fi

API_KEY=""
if [ -n "$KEY_NAME" ]; then
    API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" \
        --format="value(keyString)" 2>/dev/null || echo "")
    echo "$API_KEY" > "$PROJECT_ROOT/.api_key"
fi

echo ""
echo "Deployed: https://$PROJECT_ID.appspot.com"
[ -n "$API_KEY" ] && echo "API Key: $API_KEY"
echo ""
echo "Test with:"
echo "  curl https://$PROJECT_ID.appspot.com/api/v1/health"
