#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Deploy a static portfolio to AWS S3 + CloudFront (free tier)
#
# Cost: $0 as long as you stay under CloudFront's ALWAYS-FREE
# tier (1TB out + 10M requests/month) and S3's free tier
# (5GB storage, 20k GET/2k PUT per month, first 12 months).
# For a portfolio site this is effectively unlimited headroom.
#
# Requires: AWS CLI v2 configured (`aws configure`)
# Usage:    ./deploy.sh <bucket-name> <path-to-build-folder>
# Example:  ./deploy.sh sudheer-portfolio-2026 ./dist
# ============================================================

BUCKET_NAME="${1:?Usage: ./deploy.sh <bucket-name> <build-folder>}"
BUILD_DIR="${2:?Usage: ./deploy.sh <bucket-name> <build-folder>}"
REGION="us-east-1"   # us-east-1 required for CloudFront + ACM if adding a custom domain later

if [ ! -d "$BUILD_DIR" ]; then
  echo "Build folder '$BUILD_DIR' not found. If this is a React/Vite app, run 'npm run build' first."
  exit 1
fi

if [ ! -f "$BUILD_DIR/index.html" ]; then
  echo "WARNING: no index.html found directly inside '$BUILD_DIR'."
  echo "CloudFront's default root object is index.html — the site root will 403/AccessDenied without it."
  echo "Rename your entry file to index.html, or press Ctrl+C now to abort."
  sleep 5
fi

echo "==> 1. Creating S3 bucket (private, no public access)"
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  2>/dev/null || echo "    (bucket already exists, continuing)"

aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "==> 2. Uploading site files"
aws s3 sync "$BUILD_DIR" "s3://$BUCKET_NAME" --delete \
  --exclude ".git/*" \
  --exclude ".gitignore" \
  --exclude "deploy.sh" \
  --exclude "update.sh" \
  --exclude "ec2-setup.sh" \
  --exclude "README.md" \
  --exclude ".DS_Store"

echo "==> 3. Creating Origin Access Control (OAC) so only CloudFront can read the bucket"
OAC_ID=$(aws cloudfront list-origin-access-controls \
  --query "OriginAccessControlList.Items[?Name=='${BUCKET_NAME}-oac'].Id | [0]" --output text)

if [ -z "$OAC_ID" ] || [ "$OAC_ID" == "None" ]; then
  OAC_ID=$(aws cloudfront create-origin-access-control \
    --origin-access-control-config \
    Name="${BUCKET_NAME}-oac",SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3 \
    --query 'OriginAccessControl.Id' --output text)
  echo "    created OAC: $OAC_ID"
else
  echo "    reusing existing OAC: $OAC_ID"
fi

echo "==> 4. Creating CloudFront distribution"
DIST_CONFIG=$(cat <<EOF
{
  "CallerReference": "${BUCKET_NAME}-$(date +%s)",
  "Comment": "${BUCKET_NAME} portfolio",
  "DefaultRootObject": "index.html",
  "Enabled": true,
  "PriceClass": "PriceClass_100",
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "s3-origin",
      "DomainName": "${BUCKET_NAME}.s3.${REGION}.amazonaws.com",
      "OriginAccessControlId": "${OAC_ID}",
      "S3OriginConfig": { "OriginAccessIdentity": "" }
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"] },
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "Compress": true
  },
  "CustomErrorResponses": {
    "Quantity": 2,
    "Items": [
      { "ErrorCode": 403, "ResponsePagePath": "/index.html", "ResponseCode": "200", "ErrorCachingMinTTL": 10 },
      { "ErrorCode": 404, "ResponsePagePath": "/index.html", "ResponseCode": "200", "ErrorCachingMinTTL": 10 }
    ]
  }
}
EOF
)

DIST_JSON=$(aws cloudfront create-distribution --distribution-config "$DIST_CONFIG")
DIST_ID=$(echo "$DIST_JSON" | grep -o '"Id": "[^"]*"' | head -1 | cut -d'"' -f4)
DIST_DOMAIN=$(echo "$DIST_JSON" | grep -o '"DomainName": "[^"]*"' | head -1 | cut -d'"' -f4)

echo "==> 5. Attaching bucket policy to allow only this CloudFront distribution"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
cat > /tmp/bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFrontServicePrincipal",
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
    "Condition": {
      "StringEquals": { "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DIST_ID}" }
    }
  }]
}
EOF
aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy file:///tmp/bucket-policy.json

echo ""
echo "============================================"
echo " Deployed. CloudFront is provisioning (~5 min)."
echo " Live URL: https://${DIST_DOMAIN}"
echo " Distribution ID: ${DIST_ID}   (save this for updates)"
echo "============================================"