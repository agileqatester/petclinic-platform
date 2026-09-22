# ADR-0019: E-9 freezes the env contract for Helm values (no overlays, no apply)

**Status:** Accepted
**Date:** 2026-09-22
**Context:** Epic E-9 (`PETPLAT-45`–`48`, plus `PETPLAT-88`) still reads like Kustomize patches under `k8s/overlays/{dev,prod}/` and ends with a full deploy. That conflicts with **accepted ADR-0007** (Helm) and **accepted ADR-0018** (E-8 is namespaces and NetworkPolicies; replicas, HPA, and PDB live in Helm). The cluster is not applied, ECR has no images, and this epic does not run `kubectl apply` or `helm install`. Prod deploy is skipped. A prod object in git is allowed, same as the prod Namespace. The spec replica / HPA / PDB tables stay the course contract, but the section titles still say `k8s/overlays/` and a note claims that directory holds namespaces. Namespaces are already `k8s/base/namespaces.yaml`. ResourceQuota under the Overlays heading is **PETPLAT-89 (E-13)**. HPA needs Metrics Server (**PETPLAT-72**), which is not an E-9 install. Prod replica and HPA max counts will not schedule on **2× t4g.small**.

**Decision:** E-9 freezes the **environment scaling contract** for `helm-values/{dev,prod}.yaml`. E-16 writes the chart and those files. Do not create `k8s/overlays/`. Do not write Deployments. Do not apply anything.

### Contract (requirements only)

| Concern | Dev | Prod |
|---------|-----|------|
| Namespace | `petclinic-dev` | `petclinic-prod` |
| Replicas | 1 for all 8 services | config 2, discovery 2, api-gateway 2, customers 2, visits 2, vets 2, genai 1, admin 1 |
| Image tags | Commit SHA, never `latest` | Commit SHA (release tags only if CI adds them later) |
| HPA | Off | api-gateway 2–6 at 70% CPU; customers, visits, vets 2–4 at 70%; genai 1–3 at 70%. No HPA for config, discovery, or admin |
| PDB | Off | `minAvailable: 1` for config, discovery, api-gateway, customers, visits, vets. No PDB for genai or admin |

Image tags are updated by CI in per-service values. E-9 does not invent a tag. Metrics Server stays PETPLAT-72. ResourceQuota (max CPU 4, memory 4Gi, pods 30) stays PETPLAT-89 under `k8s/base/`, using the spec table.

E-9 does not write the chart, per-service values, Deployments, NetworkPolicies, ResourceQuotas, or Metrics Server. Prefer waiting for E-16 over a second values schema.

### Stories

| Story | After accept |
|-------|----------------|
| PETPLAT-45 / 46 | Document this contract. Not Kustomize patches. |
| PETPLAT-47 / 88 | HPA and PDB numbers for `prod.yaml`. Cluster checks and Metrics Server install leave this epic. |
| PETPLAT-48 | Deferred. Verification needs the E-16 chart, ECR images, and an applied cluster. Re-home to a post–E-16 / E-17 smoke. |
| PETPLAT-89 | Stays E-13. |
| PETPLAT-72 | Stays E-14. |

**Capacity:** 2× t4g.small cannot host the prod baseline (14 app pods at 128Mi requests, plus system pods). HPA maxima approach ~26 app pods. Do not apply prod replica or HPA counts on the learning cluster. Prod values in git are inventory until a larger pool or Karpenter exists.

**Spec delta on accept:** Retitle the overlay sections to Helm env requirements. Remove the note that `k8s/overlays/` holds namespaces. Point namespaces and ExternalSecrets at `k8s/base/`.

**Consequences:**
- Positive: One packaging path. ~$0 while nothing is applied. E-16 has a frozen contract. PETPLAT-48 is not a false pass.
- Negative: PETPLAT-47, 48, and 88 acceptance criteria change. Stories that block on PETPLAT-48 need a new dependency. Prod HA numbers do not fit the learning nodes.
- Cost: Docs are ~$0. If prod HPA max were left running on a pool sized for ~20–26 Spring pods, expect tens of USD per month in extra EC2. Do not run that scale on the student budget.
- Security: No new surface in this epic. PDB and HPA in git do not change the ADR-0018 NetworkPolicies. Namespaces stay without ResourceQuota until E-13.

**Rejected:**
- Kustomize `k8s/overlays/` — duplicates Helm (ADR-0007, ADR-0018).
- Workload YAML in E-9 — the E-16 chart owns it.
- `kubectl apply`, `helm install`, or dry-run as the acceptance gate — no cluster, chart, or images.
- Prod replica or HPA max on 2× t4g.small — will not schedule.
- Metrics Server in E-9 — PETPLAT-72.
- ResourceQuota in E-9 — PETPLAT-89.
- Keeping PETPLAT-48 in E-9 — verification cannot succeed here.

**Still applies after accept:** Spec replica, HPA, and PDB tables. ADR-0007 and ADR-0018 unchanged. E-16 encodes this contract. PETPLAT-72 before HPA works on a live cluster.
