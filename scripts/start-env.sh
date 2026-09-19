#!/usr/bin/env bash
set -euo pipefail

#
# start-env.sh — Apply the learning stack (NAT now; EKS/RDS later).
#
# Keeps the network stack. Does not start EKS (the control plane has no stop).
#
# Usage:
#   ./scripts/start-env.sh dev
#

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AWS_PROFILE="${AWS_PROFILE:-petclinic}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-central-1}"

usage() {
  echo "Usage: $0 <environment>"
  echo "  environment: dev | prod"
  echo ""
  echo "Applies terraform/environments/{env}/workload (NAT + private default routes)."
  echo "Network must already be applied. This script does not terraform apply a saved plan;"
  echo "use a saved plan.out from the workload directory for a gated apply."
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

ENV="$1"
if [[ "${ENV}" != "dev" && "${ENV}" != "prod" ]]; then
  echo "Error: environment must be 'dev' or 'prod'"
  usage
fi

if [[ "${ENV}" == "prod" ]]; then
  echo "Error: do not run prod for day-to-day learning (ADR-0001)."
  exit 1
fi

DIR="${ROOT}/terraform/environments/${ENV}/workload"
EXAMPLE="${DIR}/terraform.tfvars.example"
TFVARS="${DIR}/terraform.tfvars"

if [[ ! -f "${TFVARS}" && -f "${EXAMPLE}" ]]; then
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  sed "s/YOUR_AWS_ACCOUNT_ID/${ACCOUNT_ID}/" "${EXAMPLE}" > "${TFVARS}"
  echo "Created ${TFVARS} from example (aws_account_id from STS). Never commit it."
fi

echo "============================================"
echo "  Start learning stack: ${ENV}"
echo "  Dir: ${DIR}"
echo "  Profile: ${AWS_PROFILE}"
echo "============================================"
echo ""
echo "EKS is billed \$0.10/hour while the cluster exists. Destroy after the session:"
echo "  ./scripts/stop-env.sh ${ENV}"
echo ""
echo "This script only inits the workload module. Apply from a saved plan when you"
echo "open the plan gate. Example:"
echo "  ./scripts/write-backend-config.sh"
echo "  cd ${DIR}"
echo "  terraform init -backend-config=${ROOT}/terraform/backend.hcl"
echo "  terraform plan -var-file=terraform.tfvars -out plan.out"
echo "  terraform apply plan.out"
echo "============================================"
