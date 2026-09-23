# ADR-0022: E-13 is an IAM, security-group, and image-scan audit in git

**Status:** Accepted
**Date:** 2026-09-23
**Context:** Epic E-13 (`PETPLAT-66`–`71`) still reads as a hardening sprint: rewrite IAM until there are no `*` actions or resources, re-author NetworkPolicies, turn on image scanning, and change security groups. The code is already past that. Checkov is closed (`PETPLAT-66`). NetworkPolicy YAML is already in `k8s/base/network-policies/` (ADR-0018); live enforce waits on a cluster and PETPLAT-84. ECR `scan_on_push = true` (ADR-0014). The reference fork workflow already fails Trivy on CRITICAL (ADR-0020). EKS, LBC, ESO, GitHub OIDC, NAT, and VPC security groups are authored. This epic does not apply them. The application repo is read-only. Do not add GuardDuty, Security Hub, WAF, organization CloudTrail, a customer CMK, interface VPC endpoints, or a bastion. Kubernetes app RBAC stays with Helm (E-16). PETPLAT-89, PETPLAT-100, and PETPLAT-101 stay later E-13 stories.

**Decision:** This slice is a git audit. Do not apply Terraform. Do not rewrite NetworkPolicies. Do not fork the official LBC IAM policy. Do not replace AWS managed node, cluster, or SSM policies with custom documents. Current VPC and NAT security groups already meet the spec. Customer-authored IAM has no `Action: "*"`. The `Resource: "*"` cases that exist are required by AWS or copied from the upstream LBC policy. Document the two-layer image scan process. A live console CVE review waits until the application fork has pushed images.

### PETPLAT-68 — IAM roles in this repo

Roles audited: EKS cluster, EKS nodes (the app group and the optional observability group share one role), NAT SSM, LBC IRSA, ESO IRSA, GitHub Actions OIDC. Spec IRSA rows for EBS CSI (PETPLAT-84), optional ArgoCD, and Karpenter (E-14) are not authored yet and are outside this audit.

| Role | File | Trust | Permissions | Why |
|------|------|-------|-------------|-----|
| EKS cluster | `terraform/modules/eks/main.tf` `aws_iam_role.cluster` | `eks.amazonaws.com` (`sts:AssumeRole`, `sts:TagSession`) | AWS managed `AmazonEKSClusterPolicy` only | Spec cluster role. TagSession is required for current EKS. |
| EKS nodes | same file `aws_iam_role.node` | `ec2.amazonaws.com` | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonSSMManagedInstanceCore` | Join the cluster, CNI, pull from ECR, SSM host debug. The observability node group reuses this role (ADR-0021). IMDSv2 hop 1 on both launch templates blocks pods from using it. |
| NAT SSM | `terraform/modules/nat/main.tf` `aws_iam_role.ssm` | `ec2.amazonaws.com` | `AmazonSSMManagedInstanceCore` only | iptables repair via Session Manager (ADR-0001). |
| LBC | `terraform/environments/dev/workload/lbc.tf` + `iam-policy-lbc.json` | IRSA `kube-system:aws-load-balancer-controller`, `aud=sts.amazonaws.com` | Upstream AWS Load Balancer Controller policy v2.14.1 | Spec IRSA row. Helm install still waits on EKS apply (ADR-0016). |
| ESO | `terraform/environments/dev/workload/eso.tf` | IRSA `external-secrets:external-secrets-sa`, `aud=sts.amazonaws.com` | `secretsmanager:GetSecretValue` and `DescribeSecret` on `secret:petclinic/*` | ADR-0017. The prefix is required because Secrets Manager appends a random suffix. No `kms:Decrypt` (ADR-0012). |
| GitHub Actions | `terraform/environments/dev/network/github_oidc.tf` | `token.actions.githubusercontent.com`, subject `repo:{org}/{fork}:ref:refs/heads/main` only | `ecr:GetAuthorizationToken` on `*`; push and layer APIs on the eight `petclinic-dev/{service}` ARNs | ADR-0020. Keep-stack so push survives workload destroy. |

The EKS access entry for the applying principal uses `AmazonEKSClusterAdminPolicy`. That is the spec kubectl path, not a bastion role.

`Resource: "*"` that stay:

1. `github_oidc.tf` statement `EcrAuth` — `ecr:GetAuthorizationToken`. AWS does not support a resource ARN for that API (ADR-0020).
2. `iam-policy-lbc.json` — several statements use `"Resource": "*"`. This is the official v2.14.1 policy. Describe APIs have no resource-level ARN.
3. The AWS managed policies attached above contain their own wildcards. Replacing them is out of scope.

`petclinic/*` on ESO is a prefix, not `Resource: "*"`.

No Terraform IAM change in this slice.

### PETPLAT-71 — security groups

Authored groups: cluster, node, RDS, and ALB in `terraform/modules/vpc/security_groups.tf`, plus NAT in `terraform/modules/nat/main.tf`. The default VPC security group has no rules. No bastion group exists. No port 22 rule exists. NAT clients are the node security group.

| Spec rule | Result |
|-----------|--------|
| No SSH from `0.0.0.0/0` | Pass. No port 22 rules. |
| RDS 3306 from the node group only | Pass. |
| ALB 80/443 from the internet only | Pass. HTTP from the internet is ADR-0001. |
| Node group allows the spec set | Pass. |
| Cluster group: 443 from nodes, egress all | Pass. |
| NAT: no SSH, no inbound `0.0.0.0/0` | Pass. Ingress is from the client security groups. |
| No bastion group | Pass. |

`0.0.0.0/0` that remain are cluster egress, node egress, NAT egress, and ALB ingress on 80 and 443. No security-group edit.

### PETPLAT-69 — image-scan review

1. Before push: `.github/workflow-templates/build-push.yml` runs Trivy (`severity: CRITICAL`, `exit-code: "1"`) on the local ARM64 image. The live copy runs in the application fork (ADR-0020).
2. On push: `terraform/modules/ecr/main.tf` sets `scan_on_push = true` on every `petclinic-{env}/{service}` repository. Basic ECR scanning (ADR-0014).

A CRITICAL Trivy finding blocks the push. After the first successful fork push, the operator reviews ECR findings in the eu-central-1 console for `petclinic-dev/*`. If ECR reports CRITICAL after a push Trivy missed, do not promote the tag; fix the `eclipse-temurin:17` base image or record a dated exception. PETPLAT-70 waits on those images.

### Out of scope

| Item | Disposition |
|------|-------------|
| PETPLAT-66 Checkov | Closed. |
| PETPLAT-67 NetworkPolicy YAML | Authored under ADR-0018. Live checks wait on a cluster and PETPLAT-84. |
| PETPLAT-70 | Waits on fork images. |
| PETPLAT-89, PETPLAT-100, PETPLAT-101 | Later E-13 stories. |
| GuardDuty, Security Hub, WAF, org CloudTrail, CMK, interface VPC endpoints, bastion | Rejected. |
| `terraform apply` | Not this epic. |

**Consequences:**
- Positive: The existing least-privilege choices stay explainable. NetworkPolicies and Checkov are left as they are. Image scanning already gates the push.
- Negative: The official LBC policy stays broad. AWS managed node policies stay broad; hop limit 1 is the control against pod credential theft. ALB 80/443 stays open to the internet by design. Live NetworkPolicy and CVE checks stay open until a cluster and images exist.
- Cost (eu-central-1): about $0. IAM and security groups have no hourly charge. ECR basic scan-on-push is included with private ECR. Trivy uses GitHub Actions minutes.
- Security: Confirms the private-node and SSM posture (ADR-0001). Residual risk is the documented LBC and managed-policy breadth, and internet HTTP on the ALB until ACM exists (ADR-0016).

**Rejected:**
- Rewriting IAM to remove every `*`, including forking `iam-policy-lbc.json` or replacing AWS managed policies.
- A Terraform apply, or security-group edits, when the audit found no hole.
- GuardDuty, Security Hub, WAF, organization CloudTrail, a customer CMK, Inspector enhanced scanning, interface VPC endpoints, and a bastion.
- Re-authoring `k8s/base/network-policies/` or closing PETPLAT-67 live checks.
- PETPLAT-70 and a console CVE review before images exist.
- Kubernetes RBAC YAML in this slice (Helm, E-16).
- NAT ingress from the VPC CIDR (the node security group is the client).

**Still applies:** The spec security-group table, IRSA names, ECR scan-on-push, the Trivy CRITICAL gate, Checkov, and ADR-0001, ADR-0012, ADR-0014, ADR-0016, ADR-0017, ADR-0018, ADR-0020, and ADR-0021.
