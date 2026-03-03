#!/bin/bash
# Remove resources created by this project

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo "Error: No project set"
    exit 1
fi

echo "Project: $PROJECT_ID"
echo ""
echo "This will delete:"
echo "  - Old App Engine versions"
echo "  - API key (mobile-api-key)"
echo "  - Firestore 'users' collection"
echo "  - Local generated files"
echo ""
read -p "Continue? (y/N) " confirm
[[ ! "$confirm" =~ ^[Yy]$ ]] && exit 0

# Delete old App Engine versions
echo "Cleaning up App Engine versions..."
versions=$(gcloud app versions list --service=default \
    --format="value(version.id)" --sort-by="~version.createTime" 2>/dev/null | tail -n +2)

for v in $versions; do
    echo "  Deleting version: $v"
    gcloud app versions delete "$v" --service=default --quiet 2>/dev/null || true
done

# Delete API key
echo "Deleting API key..."
key=$(gcloud services api-keys list \
    --filter="displayName:mobile-api-key" \
    --format="value(name)" 2>/dev/null)
[ -n "$key" ] && gcloud services api-keys delete "$key" --quiet 2>/dev/null || true

# Delete Firestore data
echo "Deleting Firestore users collection..."
gcloud firestore documents delete --collection-id=users --recursive --quiet 2>/dev/null || true

# Clean local files
rm -f "$PROJECT_ROOT/.api_key"
rm -f "$PROJECT_ROOT/app/app.yaml"

echo ""
echo "Cleanup complete."
echo ""
echo "Note: App Engine app and Endpoints service are retained."
echo "To fully clean up, delete the project: gcloud projects delete $PROJECT_ID"
