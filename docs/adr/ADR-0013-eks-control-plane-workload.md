# ADR-0013: EKS control plane in the destroyable workload

**Status:** Accepted
**Date:** 2026-09-20
**Context:** Epic E-3, **dev only**. Network (E-2) is already applied: private nodes/RDS, public ALB + NAT instance, S3 gateway, baseline SGs (`eks_cluster`, `eks_node`, `rds`, `alb`). Workload/NAT is not applied. Private nodes need NAT for egress (ECR API, SSM, AL2023 HTTPS). S3 gateway covers S3/ECR *layers* only. ADR-0001 accepted that split and public+private API with `my_ip` `/32`. ADR-0012 accepted SSE-S3 / `aws/rds` (not this decision). Spec already pins EKS 1.35 STANDARD, auth `API`, 2× `t4g.small` `AL2023_ARM_64_STANDARD`, IMDSv2 hop 1, SSM on nodes, cluster logging `api`/`audit`/`authenticator`, OIDC/IRSA. Course cap ~$20; EKS $0.10/h cannot be stopped. Profile `petclinic`, region eu-central-1. ADR-0002 (“EKS over ECS”) and ADR-0003 (“Shared RDS”) stay as index decisions — this file does not reopen them. Numbered 0013 as the next written ADR after 0012. Prod is out of scope this epic.

**Decision:** Place the EKS cluster, OIDC provider, managed node group, and node/cluster IAM in `terraform/environments/dev/workload` (destroy stack), not in network. Call `terraform/modules/eks/` from that root. Cluster name `petclinic-dev`. Nodes in private subnets only. Public subnets stay tagged for ALB and keep `map_public_ip_on_launch = false`.

API: `endpoint_private_access = true`, `endpoint_public_access = true`, `public_access_cidrs` from required variable `my_ip` (`x.x.x.x/32`) passed at every workload plan/apply: `-var="my_ip=$(curl -s https://checkip.amazonaws.com)/32"`. Never commit it. Never default it. Never `0.0.0.0/0`. Re-apply workload when the laptop IP changes.

Auth: `authentication_mode = API`. Create an Access Entry for the deploying IAM principal with `AmazonEKSClusterAdminPolicy` (cluster scope). Do not manage `aws-auth`. Managed node groups in API mode get EC2_LINUX access entries from EKS. Output `aws eks update-kubeconfig --name petclinic-dev --region eu-central-1 --profile petclinic`.

Compute this epic: one On-Demand managed node group, 2× `t4g.small`, `AL2023_ARM_64_STANDARD`, 20 GB gp3, launch template IMDSv2 `http_tokens=required`, `http_put_response_hop_limit=1`. Node role: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonSSMManagedInstanceCore`. Karpenter is E-14, not E-3.

Add-ons this epic: do not add `aws_eks_addon` resources. EKS default vpc-cni, kube-proxy, and coredns are enough for `kubectl get nodes` Ready and `kubectl get pods -n kube-system`. PETPLAT-84 later pins those three, adds aws-ebs-csi-driver + IRSA (`AmazonEBSCSIDriverPolicy`), resolve-conflicts OVERWRITE, and VPC CNI NetworkPolicy.

Apply order: one workload apply. Control plane may create in parallel with NAT. Node group (and anything that needs node egress) must wait until the NAT instance ENI exists and private route tables have `0.0.0.0/0` → that ENI. Without NAT, nodes will not reach SSM or ECR API and will not become Ready.

Security groups: pass existing `eks_cluster_sg_id` / `eks_node_sg_id` from the VPC module (remote state). Do not invent a prefix list for API access. NAT ingress remains SG-to-SG from the node SG (ADR-0001).

Logging: enable `api`, `audit`, `authenticator` only. Set CloudWatch log group retention to 7 days so a forgotten cluster does not store audit forever. Do not enable controllerManager or scheduler.

Prod: do not call the module from `terraform/environments/prod/workload` this epic (skip PETPLAT-17).

**Consequences:**
- Positive: EKS hourly cost dies with `terraform destroy` of workload. kubectl from the laptop works without extra SKUs. Auth is IAM-visible. Nodes stay private; IMDSv2 hop 1 blocks pod IMDS theft. Matches saas-ntier-lab keep/destroy and ADR-0001.
- Negative: API remains internet-reachable for one `/32` (re-apply on IP change). Single-AZ NAT is still a SPOF. Default add-ons are not version-pinned until PETPLAT-84. CloudWatch ingest is a small extra bill; 7-day retention caps it.
- Rejected — EKS in network: keep stack would bill $0.10/h until someone remembers to destroy the VPC.
- Rejected — private-only API: jumphost, SSM-to-API, or interface VPCE; extra SKUs (ADR-0001).
- Rejected — Karpenter-only: no Ready nodes until E-14.
- Rejected — Terraform add-ons + EBS CSI in E-3: PETPLAT-84; no PVs yet.
- Rejected — aws-auth ConfigMap: spec is API; one-way if you start API-only.
- Rejected — prefix list instead of VPC SGs: does not replace `my_ip` `/32`; SGs already applied.
- Rejected — skip control-plane logs: required by spec; cost is cents vs $73 leftover EKS.

**Still applies after accept:** PETPLAT-12 (cluster, IAM, OIDC, logging, private subnets, additional cluster SG, `api_allowed_cidrs` from `my_ip`), PETPLAT-13 (MNG, launch template IMDS, SSM on node role, node SG, private subnets), PETPLAT-14 (Access Entry + kubeconfig output), PETPLAT-15 (wire module in **dev/workload**, not network), PETPLAT-16 (apply + 2 Ready nodes + kube-system pods). Skip PETPLAT-17. PETPLAT-84 remains later (pinned add-ons + EBS CSI). ADR-0001 and ADR-0012 unchanged.
