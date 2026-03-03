#!/bin/bash
# Enable required APIs for Cloud Endpoints + App Engine

set -e

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo "Error: No project set. Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo "Setting up project: $PROJECT_ID"

# Enable APIs
apis=(
    appengine.googleapis.com
    firestore.googleapis.com
    servicemanagement.googleapis.com
    servicecontrol.googleapis.com
    endpoints.googleapis.com
    cloudresourcemanager.googleapis.com
    apikeys.googleapis.com
    cloudbuild.googleapis.com
)

for api in "${apis[@]}"; do
    echo "Enabling $api..."
    gcloud services enable "$api" --quiet
done

# Initialize App Engine if needed
if ! gcloud app describe &>/dev/null; then
    echo ""
    echo "App Engine not initialized. Select a region:"
    echo "  1) us-central (default)"
    echo "  2) us-east1"
    echo "  3) europe-west"
    echo "  4) asia-northeast1"
    read -p "Choice [1]: " choice
    
    case $choice in
        2) region="us-east1" ;;
        3) region="europe-west" ;;
        4) region="asia-northeast1" ;;
        *) region="us-central" ;;
    esac
    
    echo "Creating App Engine app in $region..."
    gcloud app create --region="$region" --quiet
fi

# Initialize Firestore in native mode if not exists
if ! gcloud firestore databases describe --database="(default)" &>/dev/null; then
    echo "Creating Firestore database..."
    gcloud firestore databases create --location=nam5 --type=firestore-native --quiet 2>/dev/null || true
fi

# Update openapi.yaml with project ID
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENAPI_FILE="$(dirname "$SCRIPT_DIR")/openapi.yaml"

if [ -f "$OPENAPI_FILE" ] && grep -q "YOUR_PROJECT_ID" "$OPENAPI_FILE"; then
    sed -i.bak "s/YOUR_PROJECT_ID/$PROJECT_ID/g" "$OPENAPI_FILE"
    rm -f "$OPENAPI_FILE.bak"
    echo "Updated openapi.yaml with project ID"
fi

echo ""
echo "Setup complete!"
echo "Next: ./scripts/deploy.sh"
