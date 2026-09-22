# ADR-0018: E-8 is namespaces and NetworkPolicies only (Helm owns workloads)

**Status:** Accepted
**Date:** 2026-09-22
**Context:** Epic E-8 (`PETPLAT-38`–`44`) still asks for eight per-service trees under `k8s/base/{service}/` (Deployment, Service, ConfigMap, ServiceAccount, probes, JDBC env, init containers). That conflicts with **accepted ADR-0007** (Helm over plain YAML) and `.cursor/rules/kubernetes.mdc` (no per-service Deployment YAML; `k8s/base` holds namespaces, network policies, and external-secrets). ExternalSecret CRs and Ingress are already in git. Dev AWS only; cluster not applied; no `kubectl apply`. Prod deploy is skipped, but a prod Namespace object in git is allowed because the spec lists it. E-9’s intro already notes overlays become Helm values; E-16 owns the chart.

**Decision:** Narrow E-8 to **cluster objects that Helm does not template**. Do not create per-service workload YAML.

### E-8 writes (git only — no apply)

| Artifact | Location | Content |
|----------|----------|---------|
| Namespaces | `k8s/base/namespaces.yaml` | `petclinic-dev` and `petclinic-prod` |
| Labels | On each Namespace | `app.kubernetes.io/part-of=petclinic`, `environment={dev\|prod}` |
| PSA | On each Namespace | `pod-security.kubernetes.io/enforce: baseline`; `warn` and `audit`: `restricted` |
| NetworkPolicies | `k8s/base/network-policies/` | Spec table under Security Controls |

**NetworkPolicy rules:**

- Default deny ingress in `petclinic-{env}`.
- Config Server `:8888` — from pods in the same namespace.
- Discovery Server `:8761` — from pods in the same namespace.
- **API Gateway `:8080` — from public subnet CIDRs only** (ALB ENIs, LBC `target-type: ip`). Dev: `10.0.1.0/24` and `10.0.2.0/24`. Prod CIDRs only if the prod namespace policy is written. **Not** the VPC CIDR (`10.0.0.0/16`).
- Domain services `:8081`–`:8084` — from api-gateway pods only.
- Admin Server `:9090` — in-namespace only.
- Egress: config, discovery, RDS, DNS 53, HTTPS 443.

Existing `k8s/base/external-secrets/` and `k8s/base/ingress/` stay as already written. E-8 does not re-own them.

### Deferred to E-16 (Helm + `helm-values/`)

`PETPLAT-39`–`44` workload packaging: Deployments, Services, ConfigMaps, ServiceAccounts, probes, resources, JDBC / `docker,mysql` / secret refs, init containers, and per-env replica / HPA / PDB (E-9 → `helm-values/{dev,prod}.yaml`).

**Consequences:**
- Positive: One packaging path (Helm). E-8 delivers PSA + NetworkPolicy before charts exist. ~$0 (YAML only).
- Negative: `PETPLAT-39`–`44` acceptance criteria are obsolete as written. NetworkPolicies do nothing until the cluster exists and VPC CNI NetworkPolicy is enabled (PETPLAT-84). Ingress has no Deployment target until E-16.
- Rejected — eight plain YAML Deployment trees: violates ADR-0007; duplicates E-16.
- Rejected — skip NetworkPolicies until E-13 only: `k8s/base/network-policies/` is the base posture.
- Rejected — api-gateway from the full VPC CIDR: ALB ENIs sit in public subnets only.
- Rejected — omit `petclinic-prod` Namespace from git: spec lists both; the object is not a prod deploy.
- Rejected — Kustomize service overlays (E-9): values files instead (ADR-0004 superseded).

**Still applies after accept:** PETPLAT-38 (namespaces + PSA). NetworkPolicies as the E-8 companion to the spec table (no apply). **Defer** PETPLAT-39–44 to E-16. E-9 does not add Kustomize overlays. ADR-0007 unchanged.
