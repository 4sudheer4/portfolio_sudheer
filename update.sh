#!/usr/bin/env bash
set -euo pipefail

# Re-deploy after code changes: syncs new files + invalidates CDN cache
# Usage: ./update.sh <bucket-name> <path-to-build-folder> <distribution-id>

BUCKET_NAME="${1:?Usage: ./update.sh <bucket-name> <build-folder> <distribution-id>}"
BUILD_DIR="${2:?Usage: ./update.sh <bucket-name> <build-folder> <distribution-id>}"
DIST_ID="${3:?Usage: ./update.sh <bucket-name> <build-folder> <distribution-id>}"

echo "==> Syncing files"
aws s3 sync "$BUILD_DIR" "s3://$BUCKET_NAME" --delete \
  --exclude ".git/*" \
  --exclude ".gitignore" \
  --exclude "deploy.sh" \
  --exclude "update.sh" \
  --exclude "ec2-setup.sh" \
  --exclude "README.md" \
  --exclude ".DS_Store"

echo "==> Invalidating CloudFront cache"
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/*"

echo "Done. Changes will be live in ~30-60 seconds."