---
name: rollback
description: Rolls a Deployment back to the previous revision in dev or prod. Use when a deploy failed or the user asks to undo a release.
disable-model-invocation: true
---

# rollback

Roll back a failed deployment.

## Arguments

- `service` — service name or `all`
- `env` — `dev` or `prod` (default: `dev`)

## Steps

1. Namespace `petclinic-{env}`
2. Show `kubectl rollout status` and `rollout history`
3. Prod: require confirmation
4. `kubectl rollout undo deployment/{service} -n petclinic-{env}`
5. Wait for rollout; verify pods
6. For `all`, roll back application services first, then discovery, then config. Stop on first failure.
7. Suggest smoke-test after success.

## Important

- Do not retry a failed rollback — investigate first
