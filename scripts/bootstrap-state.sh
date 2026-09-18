#!/usr/bin/env bash
set -euo pipefail

#
# bootstrap-state.sh — One-time Terraform remote-state backend (PETPLAT-2)
#
# Creates (or reconciles) a customer-managed KMS CMK, an S3 bucket with
# versioning + SSE-KMS + S3 Bucket Keys + all four public-access blocks,
# and a DynamoDB lock table. Safe to run multiple times.
#
# Usage:
#   ./scripts/bootstrap-state.sh
#   ./scripts/bootstrap-state.sh --region eu-central-1
#

# Default to profile petclinic (eu-central-1). Never use account default (us-east-1).
export AWS_PROFILE="${AWS_PROFILE:-petclinic}"

REGION="eu-central-1"
KMS_ALIAS="alias/petclinic-terraform-state"
LOCK_TABLE="petclinic-terraform-locks"

usage() {
  echo "Usage: $0 [--region <aws-region>]"
  echo ""
  echo "  --region    AWS region (default: eu-central-1)"
  echo ""
  echo "Examples:"
  echo "  $0"
  echo "  $0 --region eu-central-1"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="${2:?--region requires a value}"
      shift 2
      ;;
    --region=*)
      REGION="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: unknown argument '$1'"
      usage
      ;;
  esac
done

aws_r() {
  aws --region "${REGION}" "$@"
}

TAGS_KMS=(
  "TagKey=Project,TagValue=petclinic"
  "TagKey=Environment,TagValue=shared"
  "TagKey=ManagedBy,TagValue=script"
  "TagKey=Component,TagValue=terraform-state"
)

TAGS_DDB=(
  "Key=Project,Value=petclinic"
  "Key=Environment,Value=shared"
  "Key=ManagedBy,Value=script"
  "Key=Component,Value=terraform-state"
)

echo "============================================"
echo "  Petclinic Terraform state backend"
echo "  Region: ${REGION}"
echo "============================================"
echo ""

ACCOUNT_ID="$(aws_r sts get-caller-identity --query Account --output text)"
BUCKET="petclinic-terraform-state-${ACCOUNT_ID}"
KMS_KEY_ARN=""

echo "Account: ${ACCOUNT_ID}"
echo "Bucket:  ${BUCKET}"
echo "Table:   ${LOCK_TABLE}"
echo "KMS:     ${KMS_ALIAS}"
echo ""

# --- KMS CMK (annual rotation) ---
echo "[1/3] KMS customer-managed key"

if KMS_KEY_ARN="$(aws_r kms describe-key \
  --key-id "${KMS_ALIAS}" \
  --query KeyMetadata.Arn \
  --output text 2>/dev/null)"; then
  echo "  -> Alias ${KMS_ALIAS} already exists."
else
  echo "  -> Creating CMK and alias ${KMS_ALIAS}..."
  KMS_KEY_ARN="$(aws_r kms create-key \
    --description "Petclinic Terraform state encryption (SSE-KMS)" \
    --key-usage ENCRYPT_DECRYPT \
    --customer-master-key-spec SYMMETRIC_DEFAULT \
    --tags "${TAGS_KMS[@]}" \
    --query KeyMetadata.Arn \
    --output text)"
  aws_r kms create-alias \
    --alias-name "${KMS_ALIAS}" \
    --target-key-id "${KMS_KEY_ARN}"
  echo "  -> Created ${KMS_KEY_ARN}"
fi

aws_r kms enable-key-rotation \
  --key-id "${KMS_KEY_ARN}" \
  --rotation-period-in-days 365
aws_r kms tag-resource --key-id "${KMS_KEY_ARN}" --tags "${TAGS_KMS[@]}"
echo "  -> Annual rotation enabled."
echo ""

# --- S3 bucket ---
echo "[2/3] S3 state bucket"

bucket_exists=false
if aws_r s3api head-bucket --bucket "${BUCKET}" >/dev/null 2>&1; then
  bucket_exists=true
fi

if [[ "${bucket_exists}" == true ]]; then
  echo "  -> Bucket ${BUCKET} already exists."
  LOCATION="$(aws_r s3api get-bucket-location --bucket "${BUCKET}" --query LocationConstraint --output text)"
  if [[ "${LOCATION}" == "None" ]]; then
    LOCATION="us-east-1"
  fi
  if [[ "${LOCATION}" != "${REGION}" ]]; then
    echo "Error: bucket ${BUCKET} is in ${LOCATION}, expected ${REGION}."
    exit 1
  fi
else
  echo "  -> Creating bucket ${BUCKET}..."
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws_r s3api create-bucket --bucket "${BUCKET}" >/dev/null
  else
    aws_r s3api create-bucket \
      --bucket "${BUCKET}" \
      --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  fi
fi

aws_r s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

aws_r s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

aws_r s3api put-bucket-ownership-controls \
  --bucket "${BUCKET}" \
  --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'

aws_r s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration "{
    \"Rules\": [{
      \"ApplyServerSideEncryptionByDefault\": {
        \"SSEAlgorithm\": \"aws:kms\",
        \"KMSMasterKeyID\": \"${KMS_KEY_ARN}\"
      },
      \"BucketKeyEnabled\": true
    }]
  }"

BUCKET_POLICY="$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${BUCKET}",
        "arn:aws:s3:::${BUCKET}/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    },
    {
      "Sid": "DenyIncorrectEncryptionHeader",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${BUCKET}/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption": "aws:kms"
        }
      }
    },
    {
      "Sid": "DenyUnencryptedObjectUploads",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${BUCKET}/*",
      "Condition": {
        "Null": {
          "s3:x-amz-server-side-encryption": "true"
        }
      }
    }
  ]
}
EOF
)"
aws_r s3api put-bucket-policy --bucket "${BUCKET}" --policy "${BUCKET_POLICY}"

aws_r s3api put-bucket-tagging \
  --bucket "${BUCKET}" \
  --tagging 'TagSet=[{Key=Project,Value=petclinic},{Key=Environment,Value=shared},{Key=ManagedBy,Value=script},{Key=Component,Value=terraform-state}]'

echo "  -> Versioning, SSE-KMS (Bucket Keys), public-access block, HTTPS + KMS-only upload policy applied."
echo ""

# --- DynamoDB lock table ---
echo "[3/3] DynamoDB lock table"

if aws_r dynamodb describe-table --table-name "${LOCK_TABLE}" >/dev/null 2>&1; then
  HASH_KEY="$(aws_r dynamodb describe-table \
    --table-name "${LOCK_TABLE}" \
    --query "Table.KeySchema[?KeyType=='HASH'].AttributeName | [0]" \
    --output text)"
  if [[ "${HASH_KEY}" != "LockID" ]]; then
    echo "Error: table ${LOCK_TABLE} exists but partition key is '${HASH_KEY}', expected LockID."
    exit 1
  fi
  echo "  -> Table ${LOCK_TABLE} already exists."
else
  echo "  -> Creating table ${LOCK_TABLE} (PAY_PER_REQUEST)..."
  aws_r dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --tags "${TAGS_DDB[@]}" >/dev/null
  aws_r dynamodb wait table-exists --table-name "${LOCK_TABLE}"
  echo "  -> Table is ACTIVE."
fi

TABLE_ARN="$(aws_r dynamodb describe-table \
  --table-name "${LOCK_TABLE}" \
  --query Table.TableArn \
  --output text)"
aws_r dynamodb tag-resource --resource-arn "${TABLE_ARN}" --tags "${TAGS_DDB[@]}"
echo ""

echo "============================================"
echo "  Bootstrap complete (idempotent)"
echo "============================================"
echo "  Region:         ${REGION}"
echo "  State bucket:   ${BUCKET}"
echo "  Lock table:     ${LOCK_TABLE}"
echo "  KMS key ARN:    ${KMS_KEY_ARN}"
echo "  KMS alias:      ${KMS_ALIAS}"
echo ""
echo "Next: configure terraform/environments/{dev,prod}/backend.tf (PETPLAT-3 / PETPLAT-4)"
echo "      then run terraform init in each environment."
