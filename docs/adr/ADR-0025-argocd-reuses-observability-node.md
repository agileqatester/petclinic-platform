# ADR-0025: ArgoCD reuses the observability node group

**Status:** Accepted
**Date:** 2026-09-23
**Amendment:** 2026-09-23 — [ADR-0026](ADR-0026-two-flags-one-large-node.md). `enable_observability` is restored. The node exists when either flag is true. Both stacks share the node when both flags are true. Terraform still does not install either stack.
**Context:** E-17 runs ArgoCD inside the EKS cluster (`argocd` namespace). The app pool is 2× `t4g.small` (~1.4Gi allocatable, 11 pods). Seven Spring JVMs already fill it, and dev `admin-server` stays at 0 replicas for that reason. ArgoCD (server, repo server, application controller, Redis) does not fit beside them. ADR-0021 already defines a second pool, 1× `t4g.large` (~6Gi allocatable), label `workload=observability`, taint `dedicated=observability:NoSchedule`, created only when `enable_observability=true` (default false) at **$0.0768/h**. That flag was for Prometheus, Grafana, Alertmanager, Loki, and Zipkin. Those charts are git-only and have never been installed. The workload stack is destroyed. The user asked for one flag, `argocd=true`, that brings up this same node and runs ArgoCD on it instead of the observability stack.

**Decision:** The node group stays `aws_eks_node_group.observability` (launch template, Name `petclinic-{env}-eks-observability`, IMDSv2 hop 1, encrypted gp3, app node role, min/max/desired 1, `t4g.large`). Label and taint stay `workload=observability` and `dedicated=observability:NoSchedule`. Replace the switch: `enable_argocd` (bool, default **false**) is what sets `count`. Apply with `-var=enable_argocd=true`. The next apply without the flag deletes the node. Remove `enable_observability` so there is one switch.

Terraform does not install ArgoCD. No `helm_release`. E-17 manifests in `k8s/argocd/install/` (PETPLAT-112) schedule onto that node with node selector `workload=observability` and toleration `dedicated=observability:NoSchedule`. Memory caps: application controller 512Mi, repo server 256Mi, server 128Mi, Redis 128Mi. UI is port-forward only. No public ingress. No ArgoCD IRSA. Admin password stays the in-cluster secret, never git.

An `enable_argocd=true` session does not install kube-prometheus-stack, Loki, Zipkin, or Fluent Bit. Those values stay in git. App nodes stay 2× `t4g.small`. Do not apply in this ADR.

**Consequences:**

- Positive: One extra instance, the same **$0.0768/h** as ADR-0021, and $0 when the flag is false. ArgoCD fits. The seven app services stay on the small nodes. Prometheus and ArgoCD are not billed together.
- Negative: A live observability session no longer has a flag. E-11 Helm stays git-only until a later ADR. `enable_observability` goes away, so docs that tell the operator to pass that variable are wrong after accept. The taint name still says observability while the process on the node is ArgoCD.

**Rejected:**

- ArgoCD on the 2× `t4g.small` nodes. Seven JVMs already evict a pod there.
- A third node group only for ArgoCD. Another `t4g.large` is another $0.0768/h, and the first extra node is unused while observability is not installed.
- `enable_observability=true` installing both Prometheus and ArgoCD. Requests already use ~2.2Gi of ~6Gi. Uncapped, Prometheus may use 2Gi and an uncapped ArgoCD controller another 1–2Gi. That is the eviction case.
- `t4g.xlarge` ($0.1536/h) for this session. The large node fits a capped ArgoCD without Prometheus.
- A Terraform `helm_release` for ArgoCD. ESO and the load balancer controller already install from the CLI after apply. ArgoCD stays that way.
- Renaming the label or taint to `argocd`. The pool identity from ADR-0021 stays. Only the flag and what is installed on the node change.

**On accept, fold docs only (no `.tf` until implement):** ADR-0021 amendment that this node is created by `enable_argocd` and that an ArgoCD session does not install the observability charts. Spec node table, cost row, and ADR index. `AGENTS.md` node sentence. PETPLAT-112 gains the node selector, toleration, and memory caps. PETPLAT-55 live install no longer says `enable_observability=true`.
