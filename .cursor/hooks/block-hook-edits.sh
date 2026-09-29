#!/usr/bin/env bash
# Hook: block-hook-edits.sh (preToolUse and beforeShellExecution)
# Purpose: The agent must not rewrite .cursor/hooks/ or .cursor/hooks.json.
#          Rules, skills, and agent prompts under the rest of .cursor/ stay editable.
# Fail closed: missing jq or an unreadable payload must not allow the edit.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"permission":"deny","user_message":"jq is required for safety hooks.","agent_message":"Install jq; an edit to the hook harness was blocked because the hook could not parse input."}'
  exit 2
fi

deny() {
  local msg="$1"
  jq -n --arg m "$msg" '{permission:"deny", user_message:$m, agent_message:$m}'
  exit 2
}

PATHS=$(echo "$INPUT" | jq -r '
  [
    .file_path,
    .tool_input.path,
    .tool_input.file_path,
    .tool_input.target_file,
    (.tool_input.paths // [] | .[]?)
  ]
  | map(select(. != null and . != ""))
  | .[]
')

COMMAND=$(echo "$INPUT" | jq -r '.command // .tool_input.command // empty')

is_harness_path() {
  case "$1" in
    */.cursor/hooks | */.cursor/hooks/* | */.cursor/hooks.json | \
      .cursor/hooks | .cursor/hooks/* | .cursor/hooks.json)
      return 0
      ;;
  esac
  return 1
}

MSG="BLOCKED: the agent cannot edit .cursor/hooks/ or .cursor/hooks.json. Change the hook harness in your own editor."

while IFS= read -r path; do
  [ -z "$path" ] && continue
  if is_harness_path "$path"; then
    deny "$MSG"
  fi
done <<< "$PATHS"

# A shell redirect is not the Write tool. Deny the common overwrite forms.
# Executing a hook script (bash .cursor/hooks/foo.sh) has none of these and stays allowed.
if [ -n "$COMMAND" ] && echo "$COMMAND" | grep -qF '.cursor/hooks'; then
  if echo "$COMMAND" | grep -qE '(>|>>)|[[:space:]]tee[[:space:]]|sed[[:space:]]+(-[^[:space:]]*i[^[:space:]]*|--in-place)|[[:space:]](cp|mv|rm|truncate)[[:space:]]'; then
    deny "$MSG"
  fi
fi

printf '%s\n' '{"permission":"allow"}'
exit 0
