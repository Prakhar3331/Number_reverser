#!/usr/bin/env bash
# ==============================================================================
# Helper Script to Create S3 Bucket & DynamoDB Lock Table for Terraform State
# ==============================================================================
set -e

BUCKET_NAME="${1:-}"
AWS_REGION="${2:-ap-south-1}"
DYNAMODB_TABLE="terraform-state-locks"

if [ -z "${BUCKET_NAME}" ]; then
    echo "Usage: $0 <unique-s3-bucket-name> [aws-region]"
    echo "Example: $0 my-unique-terraform-state-bucket us-east-1"
    exit 1
fi

echo "=== 1. Creating S3 Bucket for Terraform Remote State: ${BUCKET_NAME} ==="
if [ "${AWS_REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}"
else
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" \
        --create-bucket-configuration LocationConstraint="${AWS_REGION}"
fi

echo "=== 2. Enabling S3 Bucket Versioning ==="
aws s3api put-bucket-versioning --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

echo "=== 3. Enabling S3 Server-Side Encryption (AES256) ==="
aws s3api put-bucket-encryption --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'

echo "=== 4. Blocking Public Access to S3 State Bucket ==="
aws s3api put-public-access-block --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "=== 5. Creating DynamoDB Table for State Locking ==="
aws dynamodb create-table \
    --table-name "${DYNAMODB_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}" || true

echo "=== Remote Backend Setup Complete! ==="
echo "Now update 'terraform/backend.tf' with bucket = '${BUCKET_NAME}' and run 'terraform -chdir=terraform init'."
