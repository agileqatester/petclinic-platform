#!/usr/bin/env bash
# Hook: block-mcp-destroy.sh (beforeMCPExecution)
# Purpose: Block destroy via the Terraform/Terragrunt MCP tools.
# tool_input may be an object or a JSON string depending on the server.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"permission":"deny","user_message":"jq is required for safety hooks.","agent_message":"Install jq; MCP destroy was blocked because the safety hook could not parse input."}'
  exit 2
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
SERVER=$(echo "$INPUT" | jq -r '.mcp_server_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '
  if (.tool_input | type) == "object" then .tool_input.command // empty
  elif (.tool_input | type) == "string" then
    try (.tool_input | fromjson | .command // empty) catch empty
  else
    empty
  end
')

is_terraform_mcp=false
if echo "$SERVER" | grep -qiE 'terraform|terragrunt'; then
  is_terraform_mcp=true
fi
if echo "$TOOL_NAME" | grep -qiE 'Terraform|Terragrunt'; then
  is_terraform_mcp=true
fi

if [ "$is_terraform_mcp" = true ] && [ "$COMMAND" = "destroy" ]; then
  MSG="BLOCKED: destroy via MCP Terraform tool is not allowed. Run terraform destroy in your own terminal with explicit oversight."
  jq -n --arg m "$MSG" '{permission:"deny", user_message:$m, agent_message:$m}'
  exit 2
fi

printf '%s\n' '{"permission":"allow"}'
exit 0
