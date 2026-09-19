#!/usr/bin/env bash
set -euo pipefail

#
# bootstrap-state.sh — One-time Terraform remote-state backend (PETPLAT-2)
#
# Creates (or reconciles) an S3 bucket with versioning + SSE-S3 (AES256)
# + all four public-access blocks, and a DynamoDB lock table. No customer-
# managed KMS key (ADR-0012). Safe to run multiple times.
#
# Usage:
#   ./scripts/bootstrap-state.sh
#   ./scripts/bootstrap-state.sh --region eu-central-1
#

# Default to profile petclinic (eu-central-1). Never use account default (us-east-1).
export AWS_PROFILE="${AWS_PROFILE:-petclinic}"

REGION="eu-central-1"
LEGACY_KMS_ALIAS="alias/petclinic-terraform-state"
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

echo "Account: ${ACCOUNT_ID}"
echo "Bucket:  ${BUCKET}"
echo "Table:   ${LOCK_TABLE}"
echo "Encrypt: SSE-S3 (AES256)"
echo ""

# --- S3 bucket ---
echo "[1/3] S3 state bucket"

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
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": false
    }]
  }'

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
          "s3:x-amz-server-side-encryption": "AES256"
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

# Re-encrypt current objects that still use the retired CMK so the new AES256
# default actually applies (versioned buckets keep the old version).
while IFS=$'\t' read -r KEY SSE; do
  [[ -z "${KEY}" || "${KEY}" == "None" ]] && continue
  if [[ "${SSE}" != "AES256" ]]; then
    echo "  -> Rewriting s3://${BUCKET}/${KEY} to AES256"
    aws_r s3api copy-object \
      --bucket "${BUCKET}" \
      --key "${KEY}" \
      --copy-source "${BUCKET}/${KEY}" \
      --server-side-encryption AES256 \
      --metadata-directive COPY >/dev/null
  fi
done < <(aws_r s3api list-objects-v2 --bucket "${BUCKET}" --query 'Contents[].[Key,ServerSideEncryption]' --output text 2>/dev/null || true)

echo "  -> Versioning, SSE-S3 (AES256), public-access block, HTTPS + AES256-only upload policy applied."
echo ""

# --- DynamoDB lock table ---
echo "[2/3] DynamoDB lock table"

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

# --- Retire leftover CMK from the previous SSE-KMS design ---
echo "[3/3] Retire leftover customer-managed key (if any)"

if KMS_KEY_ID="$(aws_r kms describe-key --key-id "${LEGACY_KMS_ALIAS}" --query KeyMetadata.KeyId --output text 2>/dev/null)"; then
  KMS_STATE="$(aws_r kms describe-key --key-id "${KMS_KEY_ID}" --query KeyMetadata.KeyState --output text)"
  if [[ "${KMS_STATE}" == "PendingDeletion" ]]; then
    echo "  -> ${LEGACY_KMS_ALIAS} is already pending deletion."
  else
    echo "  -> Scheduling deletion of leftover CMK ${KMS_KEY_ID} (7-day window)."
    aws_r kms schedule-key-deletion \
      --key-id "${KMS_KEY_ID}" \
      --pending-window-in-days 7 >/dev/null
    aws_r kms delete-alias --alias-name "${LEGACY_KMS_ALIAS}" || true
    echo "  -> Alias removed; key pending deletion."
  fi
else
  echo "  -> No leftover alias ${LEGACY_KMS_ALIAS}."
fi
echo ""

echo "============================================"
echo "  Bootstrap complete (idempotent)"
echo "============================================"
echo "  Region:         ${REGION}"
echo "  State bucket:   ${BUCKET}"
echo "  Lock table:     ${LOCK_TABLE}"
echo "  Encryption:     SSE-S3 (AES256)"
echo ""
echo "Next: configure terraform/environments/{dev,prod}/backend.tf (PETPLAT-3 / PETPLAT-4)"
echo "      then run terraform init -reconfigure in each environment (no kms_key_id)."
