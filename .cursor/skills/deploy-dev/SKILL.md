---
name: deploy-dev
description: Deploys Petclinic services to the petclinic-dev namespace via ArgoCD, or Helm during bootstrap. Use when the user asks to deploy to dev.
disable-model-invocation: true
---

# deploy-dev

Deploy services to `petclinic-dev`.

## Arguments

- `service` — specific service or `all` (default: `all`)

## Steps

1. `kubectl config current-context`. If wrong: `aws eks update-kubeconfig --name petclinic-dev --region eu-central-1`
2. Check ArgoCD: `kubectl get namespace argocd`
3. **If ArgoCD exists:** `argocd app sync {service}-dev` or `argocd app sync -l environment=dev`, then `argocd app wait ... --timeout 120`
4. **If ArgoCD is missing (bootstrap):** Helm install in startup order (config-server, wait; discovery-server, wait; remainder) using `helm/petclinic-service/` + `helm-values/{service}.yaml` + `helm-values/dev.yaml`
5. `kubectl get pods -n petclinic-dev -o wide`. On failure, show logs (`--tail=50`).

## Important

- Dev only. Use deploy-prod for production.
- Prefer ArgoCD after E-17.
