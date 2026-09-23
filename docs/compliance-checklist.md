# Compliance checklist

Handover list for the learning stack. It records controls that are already decided. It does not add CloudTrail, GuardDuty, a customer CMK, or Kubernetes RBAC.

Status words: **authored** means the control is in git. **applied** means it exists in AWS. The workload stack is not applied. The keep network stack (VPC, ECR, GitHub OIDC) has been applied by the operator.

## Encryption at rest

AWS-managed keys only ([ADR-0012](./adr/ADR-0012-aws-managed-encryption.md)). No customer CMK.

| Data | Control | Status |
|------|---------|--------|
| RDS MySQL | `storage_encrypted = true`, AWS key `aws/rds`. `kms_key_id` is omitted | Authored, not applied |
| EBS (EKS nodes, observability node, NAT) | `encrypted = true` on the launch-template volumes | Authored, not applied |
| S3 Terraform state | SSE-S3 (AES256) is ADR-0012. HTTPS-only and AES256-only upload are `scripts/bootstrap-state.sh`. Bucket name pattern `petclinic-terraform-state-{account}` via gitignored `terraform/backend.hcl` | Applied by the bootstrap script. Not a Terraform resource in this repo |
| Secrets Manager | AWS key `aws/secretsmanager`. RDS password and optional OpenAI key | Authored, not applied |
| ECR images | `encryption_type = AES256` | Applied with the keep network stack |
| EKS secrets | AWS-managed. No customer CMK on the cluster | Authored, not applied |

## Encryption in transit

| Path | Control | Status |
|------|---------|--------|
| RDS | `require_secure_transport = 1`. JDBC `sslMode=REQUIRED` when E-16 sets it | Parameter authored. JDBC waits on Helm |
| Browser to ALB | HTTP on 80 until a domain and ACM exist ([ADR-0016](./adr/ADR-0016-dns-ingress-optional-domain.md)). 443 is open on the ALB security group and unused | Authored, not applied |
| Pod to pod | Not mTLS. NetworkPolicies are in git and do nothing until the cluster and PETPLAT-84 | Authored, not enforced |
| EKS API | Public endpoint limited to the operator `my_ip` `/32` at apply. Never `0.0.0.0/0` | Authored, not applied |
| GitHub Actions to ECR | HTTPS. OIDC, no long-lived keys | OIDC applied in the keep stack |

## IAM

Inventory and the two justified `Resource: "*"` cases are [ADR-0022](./adr/ADR-0022-e13-iam-sg-image-scan-audit.md). No authored `Action: "*"`. No bastion role.

| Role | Scope |
|------|--------|
| EKS cluster | `AmazonEKSClusterPolicy` only |
| EKS nodes (app and observability share it) | Worker node, CNI, ECR read-only, SSM core. IMDSv2 hop 1 |
| NAT | `AmazonSSMManagedInstanceCore` only |
| Load balancer controller | Upstream policy v2.14.1, including `Resource: "*"` where AWS has no ARN |
| External Secrets | `GetSecretValue` and `DescribeSecret` on `secret:petclinic/*` |
| GitHub Actions | ECR push on the eight `petclinic-dev/{service}` repos. `ecr:GetAuthorizationToken` on `*` because AWS requires it |
| kubectl | EKS access entry `AmazonEKSClusterAdminPolicy` for the applying principal. Auth mode `API` |

EBS CSI, ArgoCD, and Karpenter roles are not authored yet.

## Kubernetes access control

| Control | Status |
|---------|--------|
| Namespaces `petclinic-dev` and `petclinic-prod` | In `k8s/base/namespaces.yaml`. Not applied |
| Pod Security Admission | Enforce `baseline`, warn and audit `restricted`. Authored on `k8s/base/namespaces.yaml`. Not applied | 
| NetworkPolicies | `k8s/base/network-policies/`. Not enforced until PETPLAT-84 |
| ResourceQuota and LimitRange | `k8s/base/resource-quotas.yaml` ([ADR-0023](./adr/ADR-0023-resourcequota-limitrange-app-namespaces.md)). Not applied. Published app sizes do not admit under `limits.*` |
| App Role and RoleBinding | None in this repo. Helm (E-16) owns ServiceAccounts and workload securityContext |
| `monitoring` and `tracing` | Created by the observability charts (ADR-0021), not by `k8s/base/namespaces.yaml`. Not installed. No quota in `k8s/base/resource-quotas.yaml` |

## Audit logging

| Log | Status |
|-----|--------|
| EKS control plane | `api`, `audit`, and `authenticator` in `terraform/modules/eks/main.tf`. `controllerManager` and `scheduler` are off (ADR-0013) |
| Retention | 7 days (`cluster_log_retention_days`). CloudWatch log group uses AWS-managed encryption |
| CloudTrail | No trail resource in this repo. An organization trail was rejected (ADR-0022). This checklist does not claim the account has no trail outside the repo |
| Application logs | Loki and Fluent Bit values exist for a short session. Not installed |

## Data

Course data, not a production patient record.

| Data | Where | Protection |
|------|--------|------------|
| Owners, pets, visits | MySQL on RDS, private subnets, TLS required | Encryption at rest when applied. Not publicly accessible |
| Container images | Private ECR | Scan on push. IAM to pull |
| OpenAI API key | Secrets Manager `petclinic/{env}/openai-api-key`, only if the gated secret is set. RDS password is `petclinic/{env}/rds-credentials` | Not in git. ESO copies them into the cluster after install |
| Grafana admin password | Kubernetes Secret created at install | Never committed |
| Terraform state | S3, SSE-S3 | No account ID in git |

eu-central-1 is the region for this stack (ADR-0001). That is the residency note for the course. It is not a legal GDPR opinion. Do not load real personal data into the learning database.

## Vulnerability scanning

| When | What | Gate |
|------|------|------|
| On Terraform change | Checkov 3.2.484 via `./scripts/checkov.sh` | Critical and high fixed or skipped with a reason (PETPLAT-66, closed) |
| Before image push | Trivy in `.github/workflow-templates/build-push.yml`, fail on CRITICAL | Live copy runs in the application fork |
| On ECR push | `scan_on_push = true`, basic scanning | Console review waits until images exist (PETPLAT-70) |

## Remediation times

These apply while a stack is up. This project destroys the learning workload after a session, so a 24-hour response assumes the stack has not been destroyed.

| Severity | Time |
|----------|------|
| Critical | 24 hours |
| High | 72 hours |
| Medium | 1 week |
| Low | Next sprint |

A critical image finding blocks the push (Trivy) or stops tag promotion (ECR finding after push). A critical Terraform finding is fixed or given a `# checkov:skip=` with a reason before merge.
