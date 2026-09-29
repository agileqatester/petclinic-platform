#!/usr/bin/env bash
# Hook: ask-cluster-mutation.sh (beforeShellExecution)
# Purpose: Ask before commands that change a cluster or publish git.
#          Keep terraform destroy and prod deletes as deny, so this hook
#          cannot downgrade an earlier block if Cursor uses the last decision.
# Fail closed: missing jq must not allow a mutating command through.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"permission":"deny","user_message":"jq is required for safety hooks.","agent_message":"Install jq; the cluster-mutation hook blocked the command because it could not parse input."}'
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

ask() {
  local msg="$1"
  jq -n --arg m "$msg" '{permission:"ask", user_message:$m, agent_message:$m}'
  exit 0
}

if echo "$COMMAND" | grep -qE '(terraform|terragrunt)[[:space:]]+destroy'; then
  deny "BLOCKED: terraform destroy is not allowed via the agent. Run it in your own terminal."
fi

if echo "$COMMAND" | grep -qE '(terraform|terragrunt)[[:space:]]+apply[[:space:]]+.*-destroy'; then
  deny "BLOCKED: terraform apply -destroy is equivalent to terraform destroy. Run it in your own terminal."
fi

if echo "$COMMAND" | grep -qE 'kubectl[[:space:]]+delete[[:space:]]+(namespace|ns)[[:space:]]+petclinic-prod'; then
  deny "BLOCKED: deleting the production namespace is not allowed via the agent."
fi

if echo "$COMMAND" | grep -qE 'kubectl[[:space:]]+delete[[:space:]]+(deployment|deploy|service|svc|ingress|ing|secret|configmap|cm|pvc|persistentvolumeclaim|daemonset|ds|statefulset|sts)\b' && \
   echo "$COMMAND" | grep -qE '(-n|--namespace)[= ]?petclinic-prod'; then
  deny "BLOCKED: kubectl delete in petclinic-prod is not allowed via the agent."
fi

# Client and server dry-runs do not persist. --dry-run=none is a real apply.
if echo "$COMMAND" | grep -qE -- '--dry-run(=(client|server))?([[:space:]]|$)'; then
  printf '%s\n' '{"permission":"allow"}'
  exit 0
fi

if echo "$COMMAND" | grep -qE 'kubectl[[:space:]]+(apply|delete)([[:space:]]|$)'; then
  ask "This command changes the cluster. Argo CD is the deploy path. Approve only if you intend this call."
fi

if echo "$COMMAND" | grep -qE 'helm[[:space:]]+(install|upgrade)([[:space:]]|$)'; then
  ask "This Helm command changes the cluster. Approve only if you intend this install or upgrade."
fi

if echo "$COMMAND" | grep -qE 'argocd[[:space:]]+app[[:space:]]+sync([[:space:]]|$)'; then
  ask "argocd app sync changes the cluster. Approve only if you intend this sync."
fi

if echo "$COMMAND" | grep -qE 'git[[:space:]]+push([[:space:]]|$)'; then
  ask "git push publishes this repo. Approve only if you intend to push."
fi

printf '%s\n' '{"permission":"allow"}'
exit 0
