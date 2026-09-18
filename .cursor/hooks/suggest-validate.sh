#!/usr/bin/env bash
# Hook: suggest-validate.sh (afterFileEdit)
# Purpose: After editing infra files, suggest the matching validate command.
# Informational only — always allow.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // .tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if echo "$FILE_PATH" | grep -qE '\.tf$'; then
  TF_DIR=$(dirname "$FILE_PATH")
  echo "Tip: You edited a Terraform file. Run terraform validate in ${TF_DIR}/ and terraform fmt -check."
fi

if echo "$FILE_PATH" | grep -qE 'k8s/.*\.(yaml|yml)$'; then
  echo "Tip: You edited a K8s manifest. Validate with: kubectl apply --dry-run=client -f ${FILE_PATH}"
fi

if echo "$FILE_PATH" | grep -qE '(helm/|helm-values/).*\.(yaml|yml|tpl)$'; then
  echo "Tip: You edited a Helm file. Validate with:"
  echo "     helm template petclinic helm/petclinic-service/ -f helm-values/{service}.yaml -f helm-values/{env}.yaml"
  echo "     helm lint helm/petclinic-service/ -f helm-values/{service}.yaml -f helm-values/{env}.yaml"
fi

if echo "$FILE_PATH" | grep -qE '\.github/workflows/.*\.(yaml|yml)$'; then
  echo "Tip: You edited a GitHub Actions workflow. Review with the pipeline-reviewer agent before committing."
fi

exit 0
