#!/usr/bin/env bash
set -euo pipefail

#
# checkov.sh — Scan Terraform with Checkov (PETPLAT-66).
#
# Usage:
#   ./scripts/checkov.sh              # terraform/ (uses .checkov.yaml)
#   ./scripts/checkov.sh vpc          # terraform/modules/vpc
#   ./scripts/checkov.sh all          # same as default
#   ./scripts/checkov.sh --json       # JSON on stdout (security-scan skill)
#

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${ROOT}/.checkov.yaml"
TARGET="${ROOT}/terraform"
JSON=0

usage() {
  echo "Usage: $0 [all|vpc|nat|eks|ecr|rds|dns|secrets|observability] [--json]"
  echo ""
  echo "Scans Terraform with Checkov. Default target is terraform/."
  echo "Module names scan terraform/modules/{name} only."
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    all)
      TARGET="${ROOT}/terraform"
      shift
      ;;
    vpc|nat|eks|ecr|rds|dns|secrets|observability|karpenter)
      TARGET="${ROOT}/terraform/modules/${1}"
      shift
      ;;
    *)
      echo "Error: unknown argument '$1'"
      usage
      ;;
  esac
done

CHECKOV=""
if [[ -x "${ROOT}/.venv/bin/checkov" ]]; then
  CHECKOV="${ROOT}/.venv/bin/checkov"
elif command -v checkov >/dev/null 2>&1; then
  CHECKOV="$(command -v checkov)"
else
  echo "Error: checkov is not installed."
  echo "Create a local venv (gitignored) and install:"
  echo "  python3 -m venv .venv && .venv/bin/pip install -r requirements-checkov.txt"
  exit 127
fi

if [[ "${JSON}" -eq 0 ]]; then
  echo "============================================"
  echo "  Checkov $(${CHECKOV} --version 2>/dev/null | head -n1 || true)"
  echo "  Target: ${TARGET}"
  echo "  Config: ${CONFIG}"
  echo "============================================"
fi

ARGS=(
  -d "${TARGET}"
  --config-file "${CONFIG}"
  --framework terraform
  --skip-download
)

if [[ "${JSON}" -eq 1 ]]; then
  ARGS+=(--output json)
else
  ARGS+=(--output cli)
fi

"${CHECKOV}" "${ARGS[@]}"
