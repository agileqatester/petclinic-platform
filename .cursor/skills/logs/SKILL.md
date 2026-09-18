---
name: logs
description: Fetches pod status, events, and recent logs for a Petclinic service. Use when debugging CrashLoopBackOff, pending pods, or application errors.
disable-model-invocation: true
---

# logs

Read-only log and status dump.

## Arguments

- `service` — e.g. `api-gateway`. If omitted, show all pods in the namespace.
- `env` — `dev` or `prod` (default: `dev`)

## Steps

1. `kubectl get pods -l app.kubernetes.io/name={service} -n petclinic-{env} -o wide`
2. `kubectl describe` (tail events)
3. `kubectl logs --tail=100`
4. If CrashLoopBackOff: `--previous --tail=50`
5. `kubectl top pod` if metrics-server exists
6. Summarize status, restarts, errors, suggested actions

## Important

- Read-only. Always `--tail` in prod.
