#!/usr/bin/env bash
set -euo pipefail

#
# stop-env.sh — Destroy plan for the learning stack (NAT, later EKS/RDS/ALB).
#
# EKS cannot be "stopped". The control plane bills while the cluster exists.
# Destroys terraform/environments/{env}/workload only. Network (VPC) stays.
#
# Usage:
#   ./scripts/stop-env.sh dev
#

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AWS_PROFILE="${AWS_PROFILE:-petclinic}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-central-1}"

usage() {
  echo "Usage: $0 <environment>"
  echo "  environment: dev | prod"
  echo ""
  echo "Writes a destroy plan for terraform/environments/{env}/workload."
  echo "Does not touch network. Does not apply; use terraform apply plan.out."
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
TFVARS="${DIR}/terraform.tfvars"

echo "============================================"
echo "  Destroy learning stack: ${ENV}"
echo "  Dir: ${DIR}"
echo "  Profile: ${AWS_PROFILE}"
echo "============================================"
echo ""
echo "This writes a destroy plan for WORKLOAD only (NAT now; EKS/RDS/ALB later)."
echo "Network stays. EKS has no stop — destroy is the budget control."
echo ""
read -r -p "Type DESTROY to write the destroy plan: " confirm
if [[ "${confirm}" != "DESTROY" ]]; then
  echo "Aborted."
  exit 1
fi

"${ROOT}/scripts/write-backend-config.sh"
cd "${DIR}"
terraform init -input=false -backend-config="${ROOT}/terraform/backend.hcl"
terraform plan -destroy -var-file="${TFVARS}" -out plan.out

echo ""
echo "Destroy plan saved to ${DIR}/plan.out"
echo "Review it, then apply from that directory:"
echo "  terraform apply plan.out"
echo "Network is not in this plan (~\$0 keep stack)."
echo "============================================"
