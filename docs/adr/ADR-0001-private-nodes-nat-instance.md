# ADR-0001: Private EKS nodes with t4g.micro NAT instance

**Status:** Accepted
**Date:** 2026-09-19
**Context:** The course contract used an all-public VPC: two public subnets, IGW default route, no NAT, no VPC endpoints, security groups as the only perimeter. That was justified as saving ~$35-65/month versus NAT Gateway. Sibling labs (saas-ntier-lab NAT module, ntier-app networking notes) already run the cheaper private pattern: nodes and RDS without public IPs, one t4g.micro NAT instance for egress, S3 gateway endpoint for S3/ECR layers. Learning budget: keep the network stack on; destroy the rest after each session. Operator access must not add a bastion or SSM interface VPC endpoints. Region eu-central-1, profile petclinic, eight Spring Petclinic services on 2x t4g.small, RDS db.t4g.micro MySQL 8.4.

**Decision:** Use private subnets for EKS nodes and RDS. Keep public subnets only for the internet-facing ALB and a single t4g.micro NAT instance (AL2023 ARM, source/dest check off, IMDSv2, SSM not SSH). iptables: FORWARD DROP, RELATED/ESTABLISHED return, NEW from the VPC CIDR out the WAN iface, MASQUERADE that CIDR only. Private route tables send 0.0.0.0/0 to the NAT instance ENI while the learning stack is up. Create an S3 gateway VPC endpoint (free) on those tables. Do not create NAT Gateway. Do not create interface VPC endpoints for ECR, STS, Secrets Manager, or SSM.

Split Terraform by cost habit (same as saas-ntier-lab):

- **Network (keep):** VPC, public and private subnets, IGW, S3 gateway endpoint, route tables, baseline security groups. Idle cost ~$0 (remote state is SSE-S3; see ADR-0012).
- **Learning (destroy after the session):** NAT instance + EIP, EKS, nodes, RDS, ALB. Dev only for day-to-day learning; do not leave prod up.

Operator paths (included in this budget, no extra SKUs):

- **kubectl** to the EKS API (public+private). `public_access_cidrs` is `my_ip` `/32` passed at apply — same as saas-ntier-lab: `-var="my_ip=$(curl -s https://checkip.amazonaws.com)/32"`. Never write it to tfvars; re-apply workload when the laptop IP changes. Never `0.0.0.0/0`. Not SSM.
- **SSM Session Manager** on EKS nodes (host debug: kubelet, CNI, disk) and on the NAT instance (iptables repair only). Attach `AmazonSSMManagedInstanceCore`. No SSH port 22, no bastion. Optional SSM port-forward to RDS via a node (nodes already reach 3306). Session Manager itself is $0; agent traffic uses the NAT instance to reach public SSM endpoints while the learning stack is up. When that stack is destroyed there are no SSM targets.
- **Workload egress** via NAT: ECR API, STS, Secrets Manager, config-server Git, genai OpenAI. S3/ECR layers use the S3 gateway.

Keep IMDSv2 hop limit 1 on nodes and RDS `publicly_accessible = false`. Encryption for state and RDS is AWS-managed (ADR-0012) — no customer CMK.

**Consequences:**
- Positive: Nodes and RDS are not internet-addressable. Security groups stay required but are no longer the only control. Matches the lab/interview pattern. Extra NAT cost is about $7/month per environment only if left on ($0.0096/hour t4g.micro in eu-central-1); the accepted habit is destroy-after-session, so NAT is ~$0.01/hour during learning. Course target is under $20 AWS spend if the learning stack is destroyed after each session ($0.10/hour EKS standard; 24/7 is ~$73/month for the control plane alone). SSM and kubectl add $0. Eight services still schedule on 2x t4g.small; NAT is a separate instance.
- Negative: Single-AZ NAT instance is a single point of failure and a small operational surface (iptables, AMI, SSM). t4g.micro is burst-limited; fine for learning image pulls, not for production throughput. SSM does not work with the network stack alone (no NAT, no instances). Interface VPCEs would make SSM work without NAT but blow the budget (~$9/month per endpoint-AZ).
- Rejected — all-public IGW (course): cheapest if the only alternative is NAT Gateway, but nodes have public IPs; one open SG is an internet exposure. Savings versus this decision are ~$7/month idle, not $35-65.
- Rejected — NAT Gateway: $0.052/hour (~$38/month) per gateway in eu-central-1, times two AZs if HA, plus $0.052/GB.
- Rejected — interface VPCEs (ECR/STS/Secrets Manager/SSM) as a NAT replacement: $0.012/hour per endpoint-AZ (~$9/month each). Still cannot reach GitHub or OpenAI. Lab leaves them off in Dev.
- Rejected — SSH bastion: extra instance, key management, and an inbound path the labs already dropped (PETPLAT-71).

**Still applies after accept:** PETPLAT-6 (VPC module; add private subnets + S3 gateway; drop “no private subnets”; NAT instance belongs to the destroyable stack), PETPLAT-8 (baseline SGs + NAT instance SG, no SSH), PETPLAT-9/10/11 (wire/verify; still no NAT Gateway), PETPLAT-12/13 (EKS in private subnets; public subnets tagged for ELB; node instance profile includes SSM), PETPLAT-22 (RDS in private subnets, publicly_accessible = false), PETPLAT-71 (SG audit, no bastion), PETPLAT-76 (cost table: keep vs destroy), PETPLAT-81 (this file; not 0001-public-subnets.md). Reopen PETPLAT-7 as S3 gateway only — do not restore interface ECR/STS/Secrets Manager/SSM endpoints.
