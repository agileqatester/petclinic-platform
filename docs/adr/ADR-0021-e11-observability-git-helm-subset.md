# ADR-0021: E-11 Observability is git-only Helm values (in-cluster subset, no CloudWatch)

**Status:** Accepted
**Date:** 2026-09-22
**Context:** Epic E-11 (`PETPLAT-55`–`60`; `PETPLAT-61` removed) still reads as “deploy Prometheus, Grafana, Alertmanager, Loki, FluentBit, Zipkin, dashboards, and alert rules on EKS.” Dev workload is not applied (no EKS, NAT, or RDS). Network (VPC, ECR, GitHub OIDC) is applied. PETPLAT-84 (EBS CSI and VPC CNI NetworkPolicy) is not done, so PersistentVolumes for Prometheus, Grafana, and Loki cannot bind. Eight Spring apps and the chart are E-16; ArgoCD is E-17. Scrape targets and meaningful JVM metrics do not exist yet. Learning budget: destroy-after-session. App nodes if ever applied are 2× t4g.small. Live Prometheus uses a separate tainted node group, 1× t4g.large, created only when `enable_observability=true`. Spec and ADR-0001 already reject CloudWatch-as-default logging and alarms. The empty `terraform/modules/observability/` placeholder must not become a CloudWatch module. ADR-0018 forbids eight Deployment trees under `k8s/base`. ADR-0019 forbids overlays. No `kubectl apply` or `helm install` without a live cluster.

**Decision:** Live Prometheus, Grafana, and Alertmanager run only on a second EKS managed node group. The app group stays 2× t4g.small. The observability group is 1× `t4g.large` (8 GiB), label `workload=observability`, taint `dedicated=observability:NO_SCHEDULE`. Helm values (still git-only until a cluster exists) must set a node selector and toleration for that taint. `node-exporter` stays a DaemonSet on every node. `enable_observability` defaults to false, so a normal workload apply does not create the group or the instance. A Prometheus session passes `-var=enable_observability=true`. The next apply without that flag deletes the node. Do not apply in this change. Do not invent AWS logging resources. Loki, FluentBit, and Zipkin stay off this node.

### What E-11 writes now (git only — no apply)

| Artifact | Location | Content |
|----------|----------|---------|
| Monitoring Helm values | `helm-values/observability/dev.yaml` (and optional `prod.yaml` as inventory) | Upstream kube-prometheus-stack (or equivalent): Prometheus, Grafana, Alertmanager; node selector `workload=observability` and toleration `dedicated=observability:NoSchedule`; scrape interval 15s; retention 7d; PV sizes from spec as requirements (10Gi / 5Gi) but install remains blocked on PETPLAT-84 |
| Scrape contract | Same values file(s) | Jobs for all 8 services → `http://{service}.petclinic-{env}:{port}/actuator/prometheus` (spec table). Targets are inert until E-16 |
| Alert rules | Values / `PrometheusRule` fragments under `helm-values/observability/alerts/` | Spec table: ServiceDown, HighErrorRate, HighLatency, PodRestartLoop, HighMemoryUsage |
| Dashboards | `helm-values/observability/dashboards/` (JSON + provisioning bits referenced from values) | Service Overview, per-service ×8, JVM — provisioned via ConfigMap/sidecar pattern of the chart. Not eight Deployment YAML trees; not `k8s/overlays/` |
| Namespace | Declared in chart values (`monitoring`) | Do not duplicate app namespaces; `tracing` waits with Zipkin |

Leave `terraform/modules/observability/` as the empty placeholder (PETPLAT-1 / removed PETPLAT-61). No CloudWatch log groups, no FluentBit IRSA, no CloudWatch alarms, no customer CMK (ADR-0012).

### Deferred (not E-11 “done” until prerequisites exist)

| Concern | Waits on | Notes |
|---------|----------|--------|
| `helm install` / live UI / “metrics visible” ACs | E-3 apply (PETPLAT-16), PETPLAT-84 (EBS CSI), then a deliberate install session | No pretend deploy |
| Meaningful scrape / dashboard verification | E-16 (apps expose `/actuator/prometheus`) | Rules and scrape jobs can sit in git earlier |
| Loki + FluentBit (`PETPLAT-59`) | Same cluster + CSI; prefer after metrics subset proves useful | Extra RAM + 10Gi PV; FluentBit DaemonSet on every node |
| Zipkin (`PETPLAT-60`) | E-16 (apps export OTLP/Zipkin via config) + capacity | Remains P2; see below |
| Prod HA sizes (50Gi PVs, 15d/30d retention) | Larger pool / non-learning run | Prod values in git are inventory only |

**Optional session mode (not a second architecture):** if someone applies EKS for a short lab before CSI, use emptyDir (or disable persistence in values) so Prometheus, Grafana, and Alertmanager can start without EBS CSI. Data dies with the destroyable stack — acceptable for learning. Default git contract still documents EBS sizes for when CSI exists.

### Stack size

Author and (later) run Prometheus + Grafana + Alertmanager on the observability node group. Defer Loki, FluentBit, and Zipkin.

**Why `t4g.large`, not `t4g.medium`:** eu-central-1 on-demand Linux is $0.0384/h for `t4g.medium` (4 GiB) and $0.0768/h for `t4g.large` (8 GiB). After the kubelet reservation, a medium leaves about 3 GiB allocatable, and DaemonSets on that node take several hundred MiB more. The chart (Prometheus, Grafana, Alertmanager, operator, kube-state-metrics) then has about 2.5 GiB. Prometheus alone often sits at 1–2 GiB once cadvisor is scraped, so a medium is the size that gets OOMKilled. A large leaves about 6 GiB allocatable, enough to cap Prometheus at 2Gi and still run the rest of the chart. `t4g.xlarge` (16 GiB, $0.1536/h) is the step up only if Loki joins this node later.

The group is in the EKS module (`aws_eks_node_group.observability`), with its own launch template (same IMDSv2 hop 1 and encrypted gp3, EC2 Name `petclinic-{env}-eks-observability`) and the app node role. Instance type is on the node group. It exists only while `enable_observability` is true (count 0 otherwise), at min/max/desired 1. Apply again without the flag when the session ends so the $0.0768/h instance is destroyed.

### Grafana admin

Admin credentials are a Kubernetes Secret in `monitoring`, created at install time (Helm-generated random, or operator `kubectl create secret` / `--set` from a local secret manager). Never commit passwords, `.env`, or tfvars with the password. ESO → Secrets Manager is optional later if the team wants rotation; it is not required for E-11 git work and must not put the secret in Git. No customer CMK (ADR-0012).

### Zipkin / PETPLAT-60

Keep `PETPLAT-60` in the E-11 backlog as P2, but out of the E-11 git delivery and default install. Namespace `tracing`, port 9411, and app exporter config remain the course contract for a later session after E-16. Do not block E-11 acceptance on traces.

### Stories after accept

| Story | After accept |
|-------|----------------|
| PETPLAT-55 / 56 / 58 | Git values + alert rules for Prometheus, Grafana, and Alertmanager. Cluster ACs leave this epic until apply + CSI (+ E-16 for “metrics from all services”). |
| PETPLAT-57 | Dashboard JSON under `helm-values/observability/dashboards/` (not a second Deployment tree under `k8s/base/`). |
| PETPLAT-59 | Deferred packaging and install; still in-cluster Loki ← FluentBit, no IRSA. |
| PETPLAT-60 | Stays P2; deferred install; not required for E-11 close. |
| PETPLAT-61 | Remains removed. Placeholder module stays empty. |

**Spec delta on accept:** Observability “Implementation” → git Helm values under `helm-values/observability/`; subset vs deferred components; no apply without cluster + PETPLAT-84; Grafana Secret at install; dashboard path away from per-service Deployment trees; note capacity vs 2× t4g.small; Zipkin remains P2 deferred.

**Consequences:**
- Positive: Matches destroy-after-session and ADR-0001 (no CloudWatch default). One packaging path (upstream Helm + values). ~$0 while nothing is applied. Avoids false “deployed” acceptance criteria.
- Negative: Full-spec Loki, FluentBit, Zipkin, and live verification move later. PETPLAT-55–58 wording that assumes a running cluster is obsolete until post-apply. Dashboard path differs from the backlog’s `k8s/base/observability/grafana-dashboards/`.
- Cost (eu-central-1, order of magnitude): Git is ~$0. With the cluster up, the EKS control plane is ~$0.10/h and cannot be stopped. EBS gp3 for 10+5+10 Gi is about $2–3/month if left; destroy-after-session brings storage near $0. Observability pods themselves are mostly node RAM, not a separate AWS line item. Leaving the full stack and the apps 24/7 on undersized nodes fails scheduling and still burns EKS hours.
- Security: No secrets in git. No public scrape ingress required (port-forward). No FluentBit → CloudWatch IAM. In-cluster Alertmanager email or Slack stays operator config at install, not committed credentials.

**Rejected:**
- CloudWatch log groups, FluentBit IRSA, CloudWatch alarms (PETPLAT-61 / ADR-0001).
- `helm install` or `kubectl apply` against a cluster that is not up.
- Committing the Grafana admin password (or any secret) in values or YAML.
- Running Prometheus on the 2× t4g.small app nodes, or sizing that pool as `t4g.medium`.
- Leaving `enable_observability=true` on later applies, which keeps the `t4g.large` running.
- Eight Deployment YAML trees under `k8s/base/` or Kustomize overlays (ADR-0018 / ADR-0019).
- Filling `terraform/modules/observability/` with AWS logging resources.
- Treating E-11 as the epic that proves scrapes and dashboards without E-16.

**Still applies after accept:** Spec scrape table, alert table, PV and retention numbers as the course contract for when the stack is installed. ADR-0001, ADR-0012, ADR-0013, and ADR-0018 unchanged. PETPLAT-84 before durable PVs. E-16 before meaningful app metrics and traces.
