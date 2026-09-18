#!/usr/bin/env bash
# Hook: block-destroy.sh (beforeShellExecution)
# Purpose: Hard-block terraform destroy and production kubectl deletes.
# Fail closed: missing jq or invalid JSON must not allow the command through.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"permission":"deny","user_message":"jq is required for safety hooks.","agent_message":"Install jq; destroy/delete was blocked because the safety hook could not parse input."}'
  exit 2
fi

COMMAND=$(echo "$INPUT" | jq -r '.command // .tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  printf '%s\n' '{"permission":"allow"}'
  exit 0
fi

deny() {
  local msg="$1"
  jq -n --arg m "$msg" '{permission:"deny", user_message:$m, agent_message:$m}'
  exit 2
}

if echo "$COMMAND" | grep -qE '(terraform|terragrunt)[[:space:]]+destroy'; then
  deny "BLOCKED: terraform destroy is not allowed via the agent.

Destroying infrastructure must be done in your own terminal:
  1. terraform plan -destroy
  2. Review the plan
  3. terraform destroy

This is irreversible and can delete VPC, EKS, and RDS."
fi

if echo "$COMMAND" | grep -qE '(terraform|terragrunt)[[:space:]]+apply[[:space:]]+.*-destroy'; then
  deny "BLOCKED: terraform apply -destroy is equivalent to terraform destroy. Run it in your own terminal if intentional."
fi

if echo "$COMMAND" | grep -qE 'kubectl[[:space:]]+delete[[:space:]]+(namespace|ns)[[:space:]]+petclinic-prod'; then
  deny "BLOCKED: deleting the production namespace is not allowed via the agent. This would destroy every resource in petclinic-prod."
fi

if echo "$COMMAND" | grep -qE 'kubectl[[:space:]]+delete[[:space:]]+(deployment|deploy|service|svc|ingress|ing|secret|configmap|cm|pvc|persistentvolumeclaim|daemonset|ds|statefulset|sts)\b' && \
   echo "$COMMAND" | grep -qE '(-n|--namespace)[= ]?petclinic-prod'; then
  RESOURCE_TYPE=$(echo "$COMMAND" | grep -oE '(deployment|deploy|service|svc|ingress|ing|secret|configmap|cm|pvc|persistentvolumeclaim|daemonset|ds|statefulset|sts)' | head -1)
  deny "BLOCKED: kubectl delete ${RESOURCE_TYPE} in petclinic-prod is not allowed via the agent. Run it in your terminal after verifying impact."
fi

printf '%s\n' '{"permission":"allow"}'
exit 0
