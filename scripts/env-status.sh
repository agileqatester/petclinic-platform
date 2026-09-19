#!/usr/bin/env bash
set -euo pipefail

#
# env-status.sh — Show keep (network) vs destroy (workload) stacks.
#

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AWS_PROFILE="${AWS_PROFILE:-petclinic}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-central-1}"

usage() {
  echo "Usage: $0 <environment>"
  echo "  environment: dev | prod"
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

echo "============================================"
echo "  Environment Status: ${ENV}"
echo "  Profile: ${AWS_PROFILE}  Region: ${AWS_DEFAULT_REGION}"
echo "============================================"
echo ""

vpc_id="$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=petclinic-${ENV}-vpc" \
  --query 'Vpcs[0].VpcId' \
  --output text 2>/dev/null || echo "None")"

if [[ "${vpc_id}" == "None" || "${vpc_id}" == "None" || -z "${vpc_id}" || "${vpc_id}" == "null" ]]; then
  echo "Network (keep): VPC not found"
else
  echo "Network (keep): VPC ${vpc_id}"
fi

nat_id="$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=petclinic-${ENV}-nat" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text 2>/dev/null || echo "None")"

if [[ "${nat_id}" == "None" || -z "${nat_id}" || "${nat_id}" == "null" ]]; then
  echo "Workload (destroy): NAT instance not found"
else
  nat_state="$(aws ec2 describe-instances \
    --instance-ids "${nat_id}" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text)"
  echo "Workload (destroy): NAT ${nat_id} (${nat_state}) — billed while running"
fi

cluster_status="$(aws eks describe-cluster \
  --name "petclinic-${ENV}" \
  --query 'cluster.status' \
  --output text 2>/dev/null || echo "NOT FOUND")"
echo "EKS cluster: ${cluster_status}"
if [[ "${cluster_status}" != "NOT FOUND" ]]; then
  echo "  ** EKS bills \$0.10/hour while this exists. Destroy the workload stack. **"
fi

echo ""
echo "Keep:   terraform/environments/${ENV}/network"
echo "Destroy after session: terraform/environments/${ENV}/workload"
echo "============================================"
