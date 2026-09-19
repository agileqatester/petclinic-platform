#!/usr/bin/env bash
set -euo pipefail

#
# write-backend-config.sh — Write gitignored terraform/backend.hcl from STS.
#
# Usage:
#   ./scripts/write-backend-config.sh
#

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AWS_PROFILE="${AWS_PROFILE:-petclinic}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-central-1}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
if [[ ! "${ACCOUNT_ID}" =~ ^[0-9]{12}$ ]]; then
  echo "Error: STS did not return a 12-digit account ID."
  exit 1
fi

OUT="${ROOT}/terraform/backend.hcl"
cat > "${OUT}" <<EOF
bucket = "petclinic-terraform-state-${ACCOUNT_ID}"
EOF

echo "Wrote ${OUT} (gitignored)."
echo "Set aws_account_id = \"${ACCOUNT_ID}\" in each environment's terraform.tfvars (also gitignored)."
echo "Init with: terraform init -backend-config=${OUT}"
