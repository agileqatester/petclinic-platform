# ADR-0026: Two flags share the observability node

**Status:** Accepted
**Date:** 2026-09-23
**Context:** ADR-0025 kept one tainted `t4g.large` (`aws_eks_node_group.observability`, label `workload=observability`, taint `dedicated=observability:NoSchedule`) and replaced `enable_observability` with `enable_argocd`. That made an ArgoCD session and an observability session mutually exclusive. The user corrected that: each stack has its own flag, and both stacks run on that same node when both flags are true. ArgoCD still does not fit on the 2× `t4g.small` app nodes. The workload stack is destroyed. No ArgoCD manifests exist yet (`k8s/argocd/install/` is PETPLAT-112). Observability Helm values are git-only.

**Decision:** Restore `enable_observability` (bool, default **false**) next to `enable_argocd` (bool, default **false**). The node group `count` is 1 when either flag is true, and 0 when both are false. One instance either way. The next apply with both flags false deletes the node. Do not set either flag in tfvars.

- `-var=enable_observability=true` creates the node for Prometheus, Grafana, Alertmanager, Loki, and Zipkin. Fluent Bit stays a DaemonSet on every node.
- `-var=enable_argocd=true` creates the same node for ArgoCD. Memory caps stay: application controller 512Mi, repo server 256Mi, server 128Mi, Redis 128Mi. Node selector `workload=observability`, toleration `dedicated=observability:NoSchedule`. UI is port-forward only.
- Both true: one `t4g.large`, both stacks on it. Requests are about 2.2Gi (observability) plus about 1Gi (capped ArgoCD) on about 6Gi allocatable. Prometheus may still grow to its 2Gi limit.

Terraform does not install either stack. No `helm_release`. The operator installs the charts that match the flags after apply, the same way External Secrets is installed. This change does not write `k8s/argocd/install/`. Label, taint, launch template, and instance type stay as ADR-0021. App nodes stay 2× `t4g.small`. Do not apply in this change.

**Consequences:**

- Positive: An observability session and an ArgoCD session each have a flag again. Running both does not add a second instance. Cost stays **$0.0768/h** while the node is up, and $0 when both flags are false.
- Negative: A session with both stacks is the tight case, because Prometheus is allowed a 2Gi limit on top of the ArgoCD caps. Terraform creates the node and does not check which charts the operator installs. The taint name stays `observability` when the only workload is ArgoCD.

**Rejected:**

- ADR-0025’s single switch, which removed `enable_observability`.
- A second `t4g.large` so each stack has its own node.
- `t4g.xlarge` for the combined session.
- A Terraform `helm_release` for either stack.
- Renaming the label or taint to `argocd`.
