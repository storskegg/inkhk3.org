#!/usr/bin/env bash
BUCKET="static-site-inkhk3-org"

# 1️⃣ Get bucket region
REGION=$(aws s3api get-bucket-location --bucket "$BUCKET" --output text)

# Normalize the legacy us-east-1 case
if [[ "$REGION" == "None" || -z "$REGION" ]]; then
  REGION="us-east-1"
fi

echo "Bucket $BUCKET is in region: $REGION"

# 2️⃣ Compare with provider region (read from TF_VAR_AWS_REGION if you export it)
if [[ -n "$AWS_REGION" && "$AWS_REGION" != "$REGION" ]]; then
  echo "⚠️  Provider region ($AWS_REGION) does NOT match bucket region ($REGION)."
  echo "   Update your provider block or export AWS_REGION=$REGION"
else
  echo "✅ Provider region matches bucket region."
fi
