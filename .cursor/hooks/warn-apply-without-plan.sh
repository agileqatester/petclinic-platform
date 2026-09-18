#!/usr/bin/env bash
# Hook: warn-apply-without-plan.sh (beforeShellExecution)
# Purpose: Ask before terraform apply without a saved plan file.
# Fail-open: this is a warning, not a hard block.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"permission":"allow"}'
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.command // .tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  printf '%s\n' '{"permission":"allow"}'
  exit 0
fi

if echo "$COMMAND" | grep -qE '(terraform|terragrunt)[[:space:]]+apply'; then
  if echo "$COMMAND" | grep -qE 'apply[[:space:]]+.*\.(out|tfplan)'; then
    printf '%s\n' '{"permission":"allow"}'
    exit 0
  fi

  MSG="WARNING: terraform apply without a saved plan.

Safe workflow:
  1. terraform plan -out plan.out
  2. Review the plan
  3. terraform apply plan.out"

  if echo "$COMMAND" | grep -qE -- '-auto-approve'; then
    MSG="${MSG}

-auto-approve skips confirmation AND uses no saved plan."
  fi

  jq -n --arg m "$MSG" '{permission:"ask", user_message:$m, agent_message:$m}'
  exit 0
fi

printf '%s\n' '{"permission":"allow"}'
exit 0
