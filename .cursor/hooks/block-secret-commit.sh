#!/usr/bin/env bash
# Hook: block-secret-commit.sh (beforeShellExecution)
# Purpose: Block git add/commit of secret-like files and bulk adds.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"permission":"deny","user_message":"jq is required for safety hooks.","agent_message":"Install jq; git add/commit was blocked because the safety hook could not parse input."}'
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

if echo "$COMMAND" | grep -qE 'git[[:space:]]+(add|commit)'; then
  if echo "$COMMAND" | grep -qE 'git[[:space:]]+add[[:space:]]+(-A|--all|\.)'; then
    deny "BLOCKED: git add . / git add -A can stage secret files.

Add files explicitly by name, e.g.:
  git add terraform/modules/vpc/main.tf terraform/modules/vpc/variables.tf"
  fi

  SECRET_FILE_PATTERNS=(
    '\.env($|[[:space:]]|/)'
    '\.tfvars(\.json)?($|[[:space:]])'
    '\.pem($|[[:space:]])'
    '\.key($|[[:space:]])'
    '\.p12($|[[:space:]])'
    '\.pfx($|[[:space:]])'
    'kubeconfig'
    'aws-credentials'
    'credentials\.json'
    'credentials\.yaml'
  )

  for pattern in "${SECRET_FILE_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qiE "$pattern"; then
      deny "BLOCKED: git command matches a secret-file pattern (${pattern}).

Never commit secrets. Store them in AWS Secrets Manager. If this is a false positive, run the command in your terminal."
    fi
  done
fi

printf '%s\n' '{"permission":"allow"}'
exit 0
