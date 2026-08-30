# ==============================================================================
# Helper Script to Create S3 Bucket & DynamoDB Lock Table for Terraform State (PowerShell)
# ==============================================================================
param(
    [Parameter(Mandatory=$true)]
    [string]$BucketName,
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"
$DynamoDbTable = "terraform-state-locks"

Write-Host "=== 1. Creating S3 Bucket: $BucketName in $Region ===" -ForegroundColor Cyan
if ($Region -eq "us-east-1") {
    aws s3api create-bucket --bucket $BucketName --region $Region
} else {
    aws s3api create-bucket --bucket $BucketName --region $Region --create-bucket-configuration LocationConstraint=$Region
}

Write-Host "=== 2. Enabling S3 Bucket Versioning ===" -ForegroundColor Cyan
aws s3api put-bucket-versioning --bucket $BucketName --versioning-configuration Status=Enabled

Write-Host "=== 3. Enabling S3 Encryption (AES256) ===" -ForegroundColor Cyan
$encryptionConfig = '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-encryption --bucket $BucketName --server-side-encryption-configuration $encryptionConfig

Write-Host "=== 4. Blocking All Public Access to State Bucket ===" -ForegroundColor Cyan
aws s3api put-public-access-block --bucket $BucketName --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

Write-Host "=== 5. Creating DynamoDB Table: $DynamoDbTable ===" -ForegroundColor Cyan
try {
    aws dynamodb create-table `
        --table-name $DynamoDbTable `
        --attribute-definitions AttributeName=LockID,AttributeType=S `
        --key-schema AttributeName=LockID,KeyType=HASH `
        --billing-mode PAY_PER_REQUEST `
        --region $Region
} catch {
    Write-Host "DynamoDB table may already exist, continuing..." -ForegroundColor Yellow
}

Write-Host "`n=== Remote Backend Setup Complete! ===" -ForegroundColor Green
Write-Host "Update 'terraform/backend.tf' with bucket = '$BucketName' and run 'terraform -chdir=terraform init -migrate-state'." -ForegroundColor Green
