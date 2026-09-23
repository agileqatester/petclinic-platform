# ADR-0023: ResourceQuota and LimitRange for petclinic-dev and petclinic-prod only

**Status:** Accepted
**Date:** 2026-09-23
**Context:** PETPLAT-89 asks for ResourceQuota and LimitRange on the Petclinic app namespaces. Accepted ADR-0018 already put those namespaces and PSA labels in `k8s/base/namespaces.yaml`. Accepted ADR-0019 left ResourceQuota in E-13 under `k8s/base/`, not Helm values, and froze the spec table at max CPU 4, memory 4Gi, pods 30 for both environments. Accepted ADR-0021 puts the metrics stack in `monitoring` and Zipkin in `tracing`. Those namespaces are out of scope. The cluster is down. No `kubectl apply`. The spec container table is 100m/500m CPU and 128Mi/512Mi memory for seven services, and 200m/1000m CPU for api-gateway. The quota table does not say whether 4 CPU and 4Gi are requests, limits, or both. Eight app containers at a 512Mi limit are already 4Gi. Prod two-replica counts do not fit 4Gi of limits. Do not raise the prod quota.

**Decision:** Namespace compute guards for `petclinic-dev` and `petclinic-prod` only. One file, `k8s/base/resource-quotas.yaml`. Same numbers for both namespaces. Do not apply. Do not edit `namespaces.yaml`. Do not add objects for `monitoring` or `tracing`.

### ResourceQuota

The spec table is both requests and limits. Do not use unprefixed `cpu` or `memory` (those alias `requests.*` only).

| Key | Quantity |
|-----|----------|
| `pods` | `"30"` |
| `requests.cpu` | `"4"` |
| `requests.memory` | `4Gi` |
| `limits.cpu` | `"4"` |
| `limits.memory` | `4Gi` |

Object names: `petclinic-dev-compute` and `petclinic-prod-compute`.

### LimitRange

Type `Container` only. Defaults are the majority row of the container table, so a container that omits resources matches the app contract. Do not default every container to the api-gateway row.

| Field | CPU | Memory |
|-------|-----|--------|
| `defaultRequest` | `100m` | `128Mi` |
| `default` (limit) | `500m` | `512Mi` |
| `max` | `1000m` | `512Mi` |

`default` is at least `defaultRequest`. `max` is the highest per-container spec limit (api-gateway CPU 1000m, every service memory 512Mi) and does not exceed the namespace quota. No `min`. No `type: Pod`.

Object names: `petclinic-dev-container-defaults` and `petclinic-prod-container-defaults`. Labels: `app.kubernetes.io/part-of=petclinic` and `environment`. Not `managed-by=Helm`.

Helm (E-16) still sets explicit resources, including api-gateway 200m/1000m. LimitRange fills omissions only.

### Scheduling

Quota usage is the effective pod request and limit. Init containers at or below the app container do not add a second 512Mi. There is no headroom above 4Gi of limits.

- Dev memory limits: 8 services × 512Mi = 4Gi. The namespace is full.
- Prod baseline memory limits: 14 app pods × 512Mi = 7Gi. Prod replica counts will not admit.
- Dev CPU limits: 7 × 500m + api-gateway 1000m = 4500m. A one-replica deploy of all eight services fails `limits.cpu`.
- Prod baseline CPU limits are 8, which is over 4.

Requests still fit (dev about 900m and 1Gi; prod baseline about 1600m and 1792Mi). The cap that bites is `limits.*`. Leave the table at 4 and 4Gi. `pods: "30"` is not the binding constraint.

### PETPLAT-89

| Acceptance criterion | Disposition |
|----------------------|-------------|
| ResourceQuota per namespace | Closes when `k8s/base/resource-quotas.yaml` is in git |
| LimitRange defaults | Closes in that same file |
| Pod without requests gets defaults | Stays open until a cluster exists |
| `kubectl apply --dry-run=client` | Client-side check after the file exists. Not `kubectl apply` |

**Consequences:**
- Positive: The two app namespaces have a CPU, memory, and pod cap. Omitted containers are not BestEffort. Observability stays outside this quota. Cost is about $0.
- Negative: Published container sizes will not admit under this quota (dev CPU limits 4500m; prod memory limits 7Gi and CPU limits 8). The live check stays open.
- Security: No new IAM, security groups, or secrets. PSA labels stay as written in ADR-0018.

**Rejected:**
- Helm values for ResourceQuota (ADR-0018 / ADR-0019).
- Editing `namespaces.yaml`, or a second namespace file.
- Quotas on `monitoring` or `tracing`.
- Raising dev or prod so 4500m or 14 × 512Mi admit.
- Requests-only or limits-only hard keys.
- Unprefixed `cpu` / `memory`.
- LimitRange `type: Pod`, or `max` equal to the whole namespace quota.
- Defaulting omitted containers to api-gateway 200m/1000m.
- `kubectl apply`.

**Still applies:** The spec container table, ADR-0018, ADR-0019, and ADR-0021.
