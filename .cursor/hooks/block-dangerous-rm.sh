#!/usr/bin/env bash
# Hook: block-dangerous-rm.sh (beforeShellExecution)
# Purpose: Block rm -rf on infrastructure directories.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"permission":"deny","user_message":"jq is required for safety hooks.","agent_message":"Install jq; rm was blocked because the safety hook could not parse input."}'
  exit 2
fi

COMMAND=$(echo "$INPUT" | jq -r '.command // .tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  printf '%s\n' '{"permission":"allow"}'
  exit 0
fi

PROTECTED_DIRS="terraform k8s helm helm-values .github docs scripts .cursor"

if echo "$COMMAND" | grep -qE 'rm[[:space:]]+(-[a-zA-Z]*[rf][a-zA-Z]*[[:space:]]+|--recursive|--force)'; then
  for dir in $PROTECTED_DIRS; do
    if echo "$COMMAND" | grep -qE "rm[[:space:]].*(\s|/|^)\.?/?${dir}(/|[[:space:]]|$)"; then
      MSG="BLOCKED: cannot rm -rf ${dir}/. This directory contains critical infrastructure or agent config. Delete specific files, or use git checkout -- ${dir}/."
      jq -n --arg m "$MSG" '{permission:"deny", user_message:$m, agent_message:$m}'
      exit 2
    fi
  done
fi

printf '%s\n' '{"permission":"allow"}'
exit 0
