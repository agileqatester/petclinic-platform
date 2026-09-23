#!/usr/bin/env bash
# Lint the generic chart and render all 8 services for dev and prod (ADR-0024).
# Does not install and does not call a cluster.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
chart="${root}/helm/petclinic-service"
services=(
  config-server
  discovery-server
  api-gateway
  customers-service
  visits-service
  vets-service
  genai-service
  admin-server
)

helm lint "${chart}"

for env in dev prod; do
  for service in "${services[@]}"; do
    helm template "${service}" "${chart}" \
      -f "${root}/helm-values/${service}.yaml" \
      -f "${root}/helm-values/${env}.yaml" \
      >/dev/null
  done
done

echo "helm lint and helm template ok: 8 services x dev, prod"
