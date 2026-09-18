---
name: smoke-test
description: Runs health checks against deployed Petclinic services in dev or prod. Use after deploy or rollback to verify actuator health.
disable-model-invocation: true
---

# smoke-test

Read-only health checks.

## Arguments

- `env` — `dev` or `prod` (default: `dev`)

## Steps

1. If `scripts/smoke-test.sh` exists, run it.
2. Otherwise: list non-Running pods; port-forward each service and `curl -sf` `/actuator/health`.

| Service | Port |
|---------|------|
| config-server | 8888 |
| discovery-server | 8761 |
| api-gateway | 8080 |
| customers-service | 8081 |
| visits-service | 8082 |
| vets-service | 8083 |
| genai-service | 8084 |
| admin-server | 9090 |

3. Table of results. On failure: events + last 20 log lines.

## Important

- Read-only. Clean up port-forwards. Prefer ingress for prod.
