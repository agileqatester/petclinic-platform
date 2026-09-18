---
name: deploy-prod
description: Deploys Petclinic services to petclinic-prod via ArgoCD manual sync with confirmation. Use only when the user explicitly asks to deploy to production.
disable-model-invocation: true
---

# deploy-prod

Deploy to `petclinic-prod` with extra safety.

## Arguments

- `service` — specific service or `all` (default: `all`)

## Steps

1. Verify kubectl context is prod. Check ArgoCD is installed.
2. Ask: "You are deploying to PRODUCTION (petclinic-prod). Confirm?" Do not proceed without yes.
3. **ArgoCD path:** `argocd app diff {service}-prod`, then sync sequentially (config-server → discovery-server → rest). Stop on first failure.
4. **Bootstrap path:** Helm upgrade one service at a time with `helm-values/prod.yaml`. Stop on first failure.
5. Show pod/svc status. Suggest the smoke-test skill.

## Important

- Prod ArgoCD apps require **manual** sync
- Always show diff and get confirmation
- Sequential only — never bulk-sync prod
