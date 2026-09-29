#!/usr/bin/env bash
# Hook: block-secret-read.sh (beforeReadFile)
# Purpose: Deny agent reads of secret-shaped files.
#          .cursorignore is the control that hides the same paths from indexing.
#          *.tfvars.example stays readable.
# Fail closed: missing jq must not allow the read.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"permission":"deny","user_message":"jq is required for safety hooks."}'
  exit 2
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // .tool_input.file_path // .tool_input.path // empty')

if [ -z "$FILE_PATH" ]; then
  printf '%s\n' '{"permission":"deny","user_message":"Blocked a file read because the hook received no path."}'
  exit 2
fi

BASE=$(basename "$FILE_PATH")

deny() {
  jq -n --arg m "$1" '{permission:"deny", user_message:$m}'
  exit 2
}

case "$BASE" in
  *.tfvars.example | *.tfvars.json.example)
    printf '%s\n' '{"permission":"allow"}'
    exit 0
    ;;
  .env | .env.* | \
    *.tfvars | *.tfvars.json | \
    *.pem | *.key | *.p12 | *.pfx | \
    credentials | credentials.* | \
    kubeconfig | kubeconfig.* | \
    aws-credentials | backend.hcl)
    deny "BLOCKED: the agent cannot read ${BASE}. Secrets stay in AWS Secrets Manager, not in the chat context."
    ;;
esac

printf '%s\n' '{"permission":"allow"}'
exit 0
