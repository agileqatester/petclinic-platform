# Technical Specification — Petclinic Platform

> **Purpose:** Single source of truth for all infrastructure values. Jira stories reference sections of this document via anchor links. Read the relevant section before implementing any story.
>
> **Convention:** Dev environment is built during the course. Prod values are defined here but implementation is a **student assignment** unless noted otherwise.
>
> **Last Updated:** 2026-09-22
>
> **Implementation tags** (this clone, code in git — not a live AWS inventory):
> - **Implemented** — matching code exists and is wired (bootstrap/state also exists in AWS if `scripts/bootstrap-state.sh` was run)
> - **Partial** — skeleton, pins, or a subset only
> - **Not started** — spec only (placeholders at most)

---

## Table of Contents

| # | Section | Status |
|---|---------|--------|
| 1 | [General Project Parameters](#general-project-parameters) | Partial |
| 2 | [Terraform State Backend](#terraform-state-backend) | Implemented |
| 3 | [VPC Network Design](#vpc-network-design) | Not started |
| 4 | [Security Groups](#security-groups) | Not started |
| 5 | [EKS Cluster](#eks-cluster) | Implemented |
| 6 | [ECR Container Registry](#ecr-container-registry) | Implemented |
| 7 | [RDS Database](#rds-database) | Implemented |
| 8 | [Secrets Management](#secrets-management) | Implemented |
| 9 | [DNS and Ingress](#dns-and-ingress) | Partial |
| 10 | [Application Services](#application-services) | Not started |
| 11 | [Kubernetes Manifests](#kubernetes-manifests) | Partial |
| 12 | [Kubernetes Overlays](#kubernetes-overlays) | Partial |
| 13 | [CI/CD Pipeline](#cicd-pipeline) | Partial |
| 14 | [Observability](#observability) | Partial |
| 15 | [IRSA Roles](#irsa-roles) | Not started |
| 16 | [Security Controls](#security-controls) | Partial |
| 17 | [Scaling and Cost](#scaling-and-cost) | Not started |
| 18 | [Docker Build](#docker-build) | Not started |
| 19 | [Terraform Modules](#terraform-modules) | Partial |
| 20 | [Helm Charts](#helm-charts) | Not started |
| 21 | [GitOps with ArgoCD](#gitops-with-argocd) | Not started |
| 22 | [Karpenter (Node Autoscaling)](#karpenter-node-autoscaling) | Not started |
| 23 | [ADR Index](#adr-index) | Partial |

Cursor setup (`AGENTS.md`, `.cursor/`) is implemented (E-0) but is not a numbered spec section.

---

## General Project Parameters

**Implementation:** Partial — `eu-central-1`, Terraform `>= 1.6.0`, AWS provider `~> 6.0`, naming, and `default_tags` are set in `terraform/environments/{dev,prod}/`. EKS 1.35, RDS MySQL 8.4, and Spring versions are still spec-only.

| Parameter | Value |
|-----------|-------|
| AWS Region | `eu-central-1` |
| Availability Zones | `eu-central-1a`, `eu-central-1b` |
| Project Name | `petclinic` |
| Naming Convention | `petclinic-{env}-{resource}` (e.g., `petclinic-dev-vpc`, `petclinic-prod-eks`) |
| Environments | `dev`, `prod` |
| Terraform Version | `>= 1.6.0` |
| AWS Provider Version | `~> 6.0` |
| Kubernetes (EKS) | `1.35` (standard support; extended support is $0.60/hour — never pin it) |
| Node AMI | `AL2023_ARM_64_STANDARD` |
| RDS Engine | MySQL `8.4` |
| Spring Boot Version | `4.0.1` (parent POM: `org.springframework.boot:spring-boot-starter-parent`) |
| Spring Cloud Version | `2025.1.0` (Oakwood) |
| Java Version | `17` |

> **Version pin (Sep 2026):** EKS 1.29 is past extended support. Standard-support versions are 1.34–1.36. This course pins **1.35** (same as `saas-ntier-lab`) so add-ons and Karpenter have runway without paying extended-support pricing. AL2 AMIs are not valid for this version — use Amazon Linux 2023. AWS provider 6.x is current for greenfield modules.

### Required Tags (All AWS Resources)

| Tag Key | Value | Purpose |
|---------|-------|---------|
| `Project` | `petclinic` | Cost allocation, resource grouping |
| `Environment` | `dev` or `prod` | Environment identification |
| `ManagedBy` | `terraform` | Drift detection, ownership |

These tags are applied via `default_tags` in the AWS provider configuration. Modules accept an additional `tags` variable to merge service-specific tags.

### Optional Tags

| Tag Key | Example | When Used |
|---------|---------|-----------|
| `Service` | `customers-service` | Per-service resources (ECR repos, log groups) |
| `Component` | `networking`, `compute` | Module-level classification |

---

## Terraform State Backend

**Implementation:** Implemented — `scripts/bootstrap-state.sh` (SSE-S3 AES256, versioning, all four public-access blocks, HTTPS-deny + AES256-only bucket policy, DynamoDB `LockID`). Partial backends in `terraform/environments/{dev,prod}/{network,workload}/backend.tf`. Bucket name is not committed (`./scripts/write-backend-config.sh` → `terraform/backend.hcl`).

| Parameter | Value |
|-----------|-------|
| Backend Type | S3 with DynamoDB locking |
| S3 Bucket | `petclinic-terraform-state-{account-id}` |
| S3 Encryption | SSE-S3 (AES256). No customer CMK. Backend `encrypt = true` without `kms_key_id`. |
| S3 Versioning | Enabled |
| S3 Public Access | All blocked (4 settings) |
| DynamoDB Table | `petclinic-terraform-locks` |
| DynamoDB Partition Key | `LockID` (String) |
| Bucket policy | Deny non-TLS (`aws:SecureTransport = false`); deny PutObject without AES256 |

### Per-Environment State Keys

| Environment | State Key | Purpose |
|-------------|-----------|---------|
| Dev | `petclinic/dev/network/terraform.tfstate` | Keep stack (VPC + ECR + optional Route 53/ACM) |
| Dev | `petclinic/dev/workload/terraform.tfstate` | Destroy stack (NAT + EKS + RDS + ALB/LBC) |
| Prod | `petclinic/prod/network/terraform.tfstate` | Keep stack (do not apply for day-to-day learning) |
| Prod | `petclinic/prod/workload/terraform.tfstate` | Destroy stack |

### Bootstrap Script

`scripts/bootstrap-state.sh` provisions the S3 bucket and DynamoDB table. It is:
- Idempotent (safe to run multiple times)
- Accepts `--region` parameter (default: `eu-central-1`)
- Run once before `terraform init`

---

## VPC Network Design

**Implementation:** Implemented — `terraform/modules/vpc/` (private subnets, S3 gateway, SGs). Called from `terraform/environments/{dev,prod}/network/`. NAT default route is in the workload root.

### Architecture Decision

Private EKS nodes and RDS. Public subnets only for the internet-facing ALB and one `t4g.micro` NAT instance. S3 gateway endpoint (free). No NAT Gateway. No interface VPC endpoints. Security groups remain mandatory. See [ADR-0001](./adr/ADR-0001-private-nodes-nat-instance.md).

**Budget habit (keep vs destroy):** network stack stays on (VPC, subnets, IGW, S3 gateway, SGs, route tables, **ECR**, **optional Route 53/ACM** — idle VPC ~$0, ECR ~$1/mo after images exist, hosted zone $0.50/mo only if a domain is set). Learning stack is destroyed after each session (NAT instance + EIP, EKS, nodes, RDS, ALB/LBC). Dev only for day-to-day learning. Operator access is kubectl (EKS API `/32`) plus SSM Session Manager on nodes and NAT — no SSH, no bastion, no SSM VPCEs.

### CIDR Allocation

| Parameter | Dev | Prod |
|-----------|-----|------|
| VPC CIDR | `10.0.0.0/16` (65,536 IPs) | `10.1.0.0/16` (65,536 IPs) |
| Public Subnet 1 (AZ a) | `10.0.1.0/24` (251 usable) | `10.1.1.0/24` (251 usable) |
| Public Subnet 2 (AZ b) | `10.0.2.0/24` (251 usable) | `10.1.2.0/24` (251 usable) |
| Private Subnet 1 (AZ a) | `10.0.11.0/24` (251 usable) | `10.1.11.0/24` (251 usable) |
| Private Subnet 2 (AZ b) | `10.0.12.0/24` (251 usable) | `10.1.12.0/24` (251 usable) |

CIDRs are non-overlapping to allow future VPC peering if needed. Public subnets host ALB ENIs and the NAT instance. Private subnets host EKS nodes and RDS.

### VPC Settings

| Setting | Value |
|---------|-------|
| DNS Support | `true` |
| DNS Hostnames | `true` |
| Internet Gateway | 1 per VPC, attached |
| Public route table | `0.0.0.0/0` → IGW |
| Private route table | `0.0.0.0/0` → NAT instance ENI (only while the learning stack is up) |
| NAT Gateway | None (intentional) |
| NAT instance | One `t4g.micro`, AZ-a public subnet, EIP, AL2023 ARM, source/dest check off, IMDSv2, SSM (not SSH). iptables: `FORWARD` policy DROP; RELATED,ESTABLISHED return; NEW from `vpc_cidr` out the WAN iface; MASQUERADE that CIDR only. Destroy with the learning stack. |
| VPC Endpoints | S3 **gateway** only (free). No interface endpoints (ECR, STS, Secrets Manager, SSM). |

### Subnet Settings

| Setting | Public | Private |
|---------|--------|---------|
| `map_public_ip_on_launch` | `false` (NAT uses explicit public IP + EIP; ALB manages ENIs) | `false` |
| AZ distribution | 2 subnets across 2 AZs | 2 subnets across 2 AZs |

### EKS Subnet Tags (Required)

| Tag Key | Where | Value | Purpose |
|---------|-------|-------|---------|
| `kubernetes.io/cluster/petclinic-{env}` | Public and private | `shared` | EKS cluster association |
| `kubernetes.io/role/elb` | Public | `1` | Internet-facing ALB subnet discovery |
| `kubernetes.io/role/internal-elb` | Private | `1` | Internal ELB subnet discovery |

---

## Security Groups

**Implementation:** Slice 1 — VPC SGs in `terraform/modules/vpc/security_groups.tf`; NAT SG in `terraform/modules/nat/`.

Five security groups per environment. Security groups remain mandatory. Private subnets are an extra layer, not a replacement (ADR-0001).

Trust model (SG-to-SG except internet → ALB):

```
Internet → ALB SG :80/:443 → Node SG :8080 → RDS SG :3306
```

RDS must never allow `0.0.0.0/0`. Public subnets host only ALB + NAT.

### EKS Cluster Security Group

| Rule | Type | Protocol | Port | Source/Destination |
|------|------|----------|------|--------------------|
| API Server access from nodes | Ingress | TCP | 443 | EKS Node SG |
| API Server access from nodes | Egress | All | All | `0.0.0.0/0` |

### EKS Node Security Group

| Rule | Type | Protocol | Port | Source/Destination |
|------|------|----------|------|--------------------|
| All from cluster SG | Ingress | All | All | EKS Cluster SG |
| Inter-node communication | Ingress | All | All | Self (EKS Node SG) |
| Kubelet API from cluster | Ingress | TCP | 10250 | EKS Cluster SG |
| API Gateway from ALB (LBC IP targets) | Ingress | TCP | 8080 | ALB SG |
| All outbound | Egress | All | All | `0.0.0.0/0` |

### RDS Security Group

| Rule | Type | Protocol | Port | Source/Destination |
|------|------|----------|------|--------------------|
| MySQL from nodes | Ingress | TCP | 3306 | EKS Node SG |
| No other ingress | — | — | — | — |

**Critical:** RDS SG allows `3306` from EKS Node SG **only**. Never `0.0.0.0/0`.

### ALB Security Group

| Rule | Type | Protocol | Port | Source/Destination |
|------|------|----------|------|--------------------|
| HTTP from internet | Ingress | TCP | 80 | `0.0.0.0/0` |
| HTTPS from internet | Ingress | TCP | 443 | `0.0.0.0/0` |
| To api-gateway pods (LBC `target-type: ip`) | Egress | TCP | 8080 | EKS Node SG |

### NAT Instance Security Group

| Rule | Type | Protocol | Port | Source/Destination |
|------|------|----------|------|--------------------|
| Client traffic to NAT | Ingress | All | All | EKS Node SG (SG-to-SG, not VPC CIDR) |
| All outbound | Egress | All | All | `0.0.0.0/0` |

**Critical:** No SSH `:22`. Operator access to the NAT box is SSM Session Manager only (iptables repair). No inbound from `0.0.0.0/0`.

---

## EKS Cluster

**Implementation:** Implemented — `terraform/modules/eks/` wired from `terraform/environments/dev/workload/` (ADR-0013). Not applied. Prod not wired (`PETPLAT-17` skipped). NAT + private default route must exist **before** the managed node group can become Ready. Control plane does not need NAT. S3 gateway is not a NAT substitute for ECR API or SSM. E-3 add-ons: EKS defaults (coredns, kube-proxy, vpc-cni). Pinned `aws_eks_addon` + EBS CSI + CNI NetworkPolicy = PETPLAT-84. kubectl auth: Access Entries, `authentication_mode = API`, no aws-auth. Cluster logging CloudWatch retention **7 days**.

### Cluster Configuration

| Parameter | Dev | Prod |
|-----------|-----|------|
| Cluster Name | `petclinic-dev` | `petclinic-prod` |
| Kubernetes Version | `1.35` | `1.35` |
| Support type | `STANDARD` (`upgrade_policy.support_type`) | `STANDARD` |
| API Server Endpoint | Public + private. `public_access_cidrs` = **`my_ip` `/32`**, never `0.0.0.0/0`. Pass at apply (see Operator IP). | Same |
| Authentication Mode | `API` (no aws-auth ConfigMap) | `API` |
| Cluster Logging | `api`, `audit`, `authenticator` (CloudWatch retention **7 days**) | Same |
| Subnets | Private (nodes); public remain tagged for ALB | Same |

### Cluster IAM Role

| Policy | Type |
|--------|------|
| `AmazonEKSClusterPolicy` | AWS Managed |

### OIDC Provider

Created from EKS cluster identity issuer URL. Required for IRSA (IAM Roles for Service Accounts).

### Managed Node Group

| Parameter | Dev | Prod |
|-----------|-----|------|
| Node Group Name | `petclinic-dev-nodes` | `petclinic-prod-nodes` |
| Instance Types | `["t4g.small"]` | `["t4g.small"]` |
| Architecture | ARM64 (Graviton) | ARM64 (Graviton) |
| Capacity Type | `ON_DEMAND` (Graviton free trial until Dec 2026 — after that, Spot via Karpenter) | `ON_DEMAND` |
| Min Size | 2 | 2 |
| Max Size | 4 | 4 |
| Desired Size | 2 | 2 |
| Disk Size | 20 GB gp3 | 20 GB gp3 |
| AMI Type | `AL2023_ARM_64_STANDARD` | `AL2023_ARM_64_STANDARD` |
| IMDS | `http_tokens = required`, `http_put_response_hop_limit = 1` | Same |

> **Cost note:** t4g.small instances (2 vCPU, 2 GiB) are eligible for the AWS Graviton free trial (750 hrs/month until Dec 2026). Both dev and prod use identical sizing — this is a cost optimization for a learning project. In production, you would use larger instances (e.g., m7g.xlarge). Students should understand this trade-off.

### Observability node group (ADR-0021)

Dev only. Created only when `enable_observability=true` on the workload apply. Default false: no node group and no instance. The next apply without the flag deletes it. Prod is not wired.

| Parameter | Dev |
|-----------|-----|
| Node Group Name | `petclinic-dev-observability` |
| Instance Types | `["t4g.large"]` (8 GiB). Not `t4g.medium`. |
| Min / Max / Desired | 1 / 1 / 1 while the flag is true |
| AMI / IMDS / disk | Same as the app group: `AL2023_ARM_64_STANDARD`, IMDSv2 hop 1, 20 GB encrypted gp3 |
| Launch template Name | `petclinic-dev-eks-observability` (own template; same security posture) |
| Label | `workload=observability` |
| Taint | `dedicated=observability:NO_SCHEDULE` |
| Price while up | $0.0768/h (eu-central-1 On-Demand Linux). $0 when the flag is false |

Prometheus, Grafana, and Alertmanager schedule here. `node-exporter` stays a DaemonSet on every node. Loki and Zipkin do not use this node. App pods stay on `petclinic-dev-nodes`.

### Node IAM Role Policies

| Policy | Type |
|--------|------|
| `AmazonEKSWorkerNodePolicy` | AWS Managed |
| `AmazonEKS_CNI_Policy` | AWS Managed |
| `AmazonEC2ContainerRegistryReadOnly` | AWS Managed |
| `AmazonSSMManagedInstanceCore` | AWS Managed (Session Manager; no SSH) |

### EKS Managed Add-ons

| Add-on | Purpose | IRSA Required |
|--------|---------|---------------|
| `coredns` | Cluster DNS | No |
| `kube-proxy` | Network proxy | No |
| `vpc-cni` | Pod networking | No |
| `aws-ebs-csi-driver` | EBS PersistentVolumes (Prometheus, Grafana) | Yes (`AmazonEBSCSIDriverPolicy`) |

E-3 (ADR-0013): do **not** manage add-ons in Terraform. EKS installs default vpc-cni, kube-proxy, and coredns. PETPLAT-84 later: pin versions (not `latest`), `aws-ebs-csi-driver` + IRSA, resolve conflicts `OVERWRITE`, enable VPC CNI NetworkPolicy (`enableNetworkPolicy: "true"`).

### Node launch template (required for IMDS)

Managed node groups must use a launch template so IMDS cannot be reached from pods:

```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required" # IMDSv2 only
  http_put_response_hop_limit = 1          # pods cannot use the node role
}
```

Disk type: `gp3`, encrypted. Do not rely on node-group `disk_size` alone if the launch template owns the block device mapping.

### Adding kubectl users

The applying IAM principal gets an Access Entry with `AmazonEKSClusterAdminPolicy` (cluster scope). To grant another user or role: add `aws_eks_access_entry` + `aws_eks_access_policy_association` (do not use aws-auth). Then:

```
aws eks update-kubeconfig --name petclinic-dev --region eu-central-1 --profile petclinic
```

---

## ECR Container Registry

**Implementation:** Implemented — `terraform/modules/ecr/` wired from `terraform/environments/dev/network/` (ADR-0014). Not applied. Prod not wired. Apply is a later PETPLAT-20 gate (network plan/apply; does not require E-3). Encryption AES256 (ECR default; no customer CMK — ADR-0012). Private only (ADR-0010).

### Repository Configuration

| Parameter | Dev | Prod |
|-----------|-----|------|
| Registry Type | ECR Private | ECR Private |
| Terraform Resource | `aws_ecr_repository` | `aws_ecr_repository` |
| Region | `eu-central-1` (same as infra) | `eu-central-1` |
| Tag Mutability | `MUTABLE` | `IMMUTABLE` |
| Image Scanning | Scan-on-push enabled | Scan-on-push enabled |
| Encryption | AES256 (default) | AES256 (default) |

### Repositories (8 per environment)

| Repository Name | Service | Image URI Pattern |
|-----------------|---------|-------------------|
| `petclinic-{env}/config-server` | Config Server | `{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/config-server:{tag}` |
| `petclinic-{env}/discovery-server` | Discovery Server | `{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/discovery-server:{tag}` |
| `petclinic-{env}/api-gateway` | API Gateway | `{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/api-gateway:{tag}` |
| `petclinic-{env}/customers-service` | Customers Service | `{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/customers-service:{tag}` |
| `petclinic-{env}/visits-service` | Visits Service | `{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/visits-service:{tag}` |
| `petclinic-{env}/vets-service` | Vets Service | `{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/vets-service:{tag}` |
| `petclinic-{env}/genai-service` | GenAI Service | `{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/genai-service:{tag}` |
| `petclinic-{env}/admin-server` | Admin Server | `{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/admin-server:{tag}` |

### ECR Authentication

```bash
# Login (same region as infra)
aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin {account}.dkr.ecr.eu-central-1.amazonaws.com

# Push
docker push {account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/{service}:{tag}
```

### Image Tag Strategy

| Context | Tag Format | Example |
|---------|------------|---------|
| CI/CD builds | Short commit SHA (7 chars) | `a1b2c3d` |
| Initial manual push | Semantic version | `v1.0.0` |
| Never used | `latest` | — |

### Lifecycle Policies

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Expire untagged images after 7 days",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 7
      },
      "action": { "type": "expire" }
    },
    {
      "rulePriority": 2,
      "description": "Keep last 10 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": { "type": "expire" }
    }
  ]
}
```

### Cost

ECR Private: 500 MB free tier, then $0.10/GB/month. With 8 services at ~200 MB each, total storage is ~8-10 GB = **~$1/month** beyond free tier. Negligible cost that buys production-correct patterns: private images, lifecycle policies, scan-on-push, tag immutability.

---

## RDS Database

**Implementation:** Implemented — `terraform/modules/rds/` wired from `terraform/environments/dev/workload/` (ADR-0015). Not applied. Prod not wired (`PETPLAT-27` skipped). Credentials in this module (`petclinic/{env}/rds-credentials`). No `depends_on` NAT. Skip PETPLAT-26 apply this epic.

### Instance Configuration

| Parameter | Dev | Prod |
|-----------|-----|------|
| Engine | MySQL 8.4 | MySQL 8.4 |
| Instance Class | `db.t4g.micro` | `db.t4g.micro` |
| Multi-AZ | `false` | `false` (single-AZ, cost optimization for learning) |
| Allocated Storage | 20 GB | 20 GB |
| Max Allocated Storage (autoscaling) | 20 GB | 20 GB |
| Storage Type | `gp3` | `gp3` |
| Storage Encrypted | `true`, AWS-managed `aws/rds` (omit `kms_key_id`) | same |
| Publicly accessible | `false` (private subnets; no IGW route) | `false` (private subnets; no IGW route) |
| Backup Retention | 7 days | 7 days |
| Skip Final Snapshot | `true` | `false` |
| Deletion Protection | `false` | `true` |
| DB Identifier | `petclinic-dev-mysql` | `petclinic-prod-mysql` |
| Master Username | `petclinic` | `petclinic` |
| Master Password | Generated in the RDS module via `random_password` (not a variable / tfvars) | same |
| DB name | `petclinic` (shared; ADR-0003) | `petclinic` |
| Terraform root | `environments/dev/workload` (ADR-0015) | skip this epic |

> **Cost note:** `db.t4g.micro` OnDemand in eu-central-1 is **~$0.019/hour** (~$14/month if left 24/7). Free tier (750 hrs/12 months, 20 GB) can make a session ~$0, but 24/7 still burns the allowance — destroy with workload. Storage encryption uses the AWS-managed `aws/rds` key (no $1/month CMK). `max_allocated_storage = 20` matches allocated storage: **autoscaling is off**. In a real production you would use Multi-AZ, larger instance classes, 30-day backups, deletion protection, and a final snapshot.

### Parameter Group

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `character_set_server` | `utf8mb4` | Full Unicode support |
| `collation_server` | `utf8mb4_unicode_ci` | Unicode collation |
| `require_secure_transport` | `1` (`ON`) | Reject plaintext MySQL (RDS TLS). JDBC: `sslMode=REQUIRED`. |

### Database Schema

All three database services use a shared `petclinic` database. Each service's schema.sql begins with `CREATE DATABASE IF NOT EXISTS petclinic; USE petclinic;`.

#### Tables (7 total across 3 services)

**Customers Service** — 3 tables:

| Table | Columns | Foreign Keys |
|-------|---------|-------------|
| `types` | `id` (PK, AUTO_INCREMENT), `name` | None |
| `owners` | `id` (PK), `first_name`, `last_name`, `address`, `city`, `telephone` | None |
| `pets` | `id` (PK), `name`, `birth_date`, `type_id`, `owner_id` | `owner_id` → `owners(id)`, `type_id` → `types(id)` |

**Vets Service** — 3 tables:

| Table | Columns | Foreign Keys |
|-------|---------|-------------|
| `vets` | `id` (PK, AUTO_INCREMENT), `first_name`, `last_name` | None |
| `specialties` | `id` (PK), `name` | None |
| `vet_specialties` | `vet_id`, `specialty_id` | `vet_id` → `vets(id)`, `specialty_id` → `specialties(id)` |

**Visits Service** — 1 table:

| Table | Columns | Foreign Keys |
|-------|---------|-------------|
| `visits` | `id` (PK, AUTO_INCREMENT), `pet_id`, `visit_date`, `description` | `pet_id` → `pets(id)` |

#### Schema Initialization Order

**Critical:** The `visits` table has `FOREIGN KEY (pet_id) REFERENCES pets(id)`, which is in the customers service schema. Initialization order:

1. **Customers Service** schema — creates `types`, `owners`, `pets`
2. **Vets Service** schema — creates `vets`, `specialties`, `vet_specialties` (independent)
3. **Visits Service** schema — creates `visits` (depends on `pets` from step 1)

**Strategy:** Let Spring Boot auto-initialize schemas on first startup with `spring.sql.init.mode=always` and `mysql` profile. The init order is enforced by deploying customers-service before visits-service.

### Connection String Format

```
jdbc:mysql://{rds-endpoint}:3306/petclinic?sslMode=REQUIRED
```

Example: `jdbc:mysql://petclinic-dev-mysql.abc123.eu-central-1.rds.amazonaws.com:3306/petclinic?sslMode=REQUIRED`

`sslMode=REQUIRED` (MySQL Connector/J 8) encrypts the session. It does **not** verify the Amazon RDS CA. `VERIFY_CA` / `VERIFY_IDENTITY` need the RDS CA in the trust store (later, if the image can mount it). Without `sslMode=REQUIRED`, `require_secure_transport=ON` returns MySQL error 3159.

---

## Secrets Management

**Implementation:** Implemented — `terraform/modules/secrets/` wired from `terraform/environments/dev/workload/` (ADR-0017). OpenAI secret only when `openai_api_key` is non-empty (default empty). ESO IRSA in `eso.tf`. ClusterSecretStore + ExternalSecret YAML in `k8s/base/external-secrets/`. Not applied. ESO install waits on E-3.

### Why AWS Secrets Manager

AWS Secrets Manager is purpose-built for storing secrets (database credentials, API keys). It provides built-in rotation, cross-account access, and fine-grained IAM policies. **$0.40/secret/month** in Frankfurt while the secret exists. Keep-stack secrets fight destroy-after-session. RDS + optional OpenAI live in **workload** (ADR-0015 / ADR-0017): **$0** after destroy (`recovery_window_in_days = 0`). Git credential secrets are skipped (public config repo).

### Secrets

| Secret Name | Type | Content | Created By |
|-------------|------|---------|------------|
| `petclinic/{env}/rds-credentials` | JSON (`{"username":"...","password":"..."}`) | RDS master credentials | RDS module (PETPLAT-23) |
| `petclinic/{env}/openai-api-key` | Plaintext | OpenAI API key value | Secrets module (PETPLAT-33) |

> **Note:** Secret names use forward-slash convention (`petclinic/{env}/...`). All secrets are encrypted with the default AWS KMS key (`aws/secretsmanager`).

RDS credentials are created by the RDS module **in workload** (ADR-0015) with `random_password` (16+ chars, MySQL-safe special characters) and stored as a JSON object. `recovery_window_in_days = 0` so destroy does not leave a 30-day replica. The secrets module handles non-RDS secrets only.

### External Secrets Operator (ESO)

| Parameter | Value |
|-----------|-------|
| Installation | kubectl apply (CRDs + controller) |
| Namespace | `external-secrets` |
| Store Type | `ClusterSecretStore` |
| Provider | AWS Secrets Manager |
| Auth | IRSA (see [IRSA Roles](#irsa-roles)) |

### ClusterSecretStore Configuration

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-central-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

### ExternalSecret Manifests

**RDS Credentials** (`k8s/base/external-secrets/rds-credentials.yaml`):

| Field | Value |
|-------|-------|
| `secretStoreRef.name` | `aws-secrets-manager` |
| `secretStoreRef.kind` | `ClusterSecretStore` |
| `refreshInterval` | `1h` |
| `target.name` | `rds-credentials` |
| `data[0].secretKey` | `username` |
| `data[0].remoteRef.key` | `petclinic/{env}/rds-credentials` |
| `data[0].remoteRef.property` | `username` |
| `data[1].secretKey` | `password` |
| `data[1].remoteRef.key` | `petclinic/{env}/rds-credentials` |
| `data[1].remoteRef.property` | `password` |

**OpenAI API Key** (`k8s/base/external-secrets/openai-api-key.yaml`):

| Field | Value |
|-------|-------|
| `refreshInterval` | `1h` |
| `target.name` | `openai-api-key` |
| `data[0].secretKey` | `OPENAI_API_KEY` |
| `data[0].remoteRef.key` | `petclinic/{env}/openai-api-key` |

---

## DNS and Ingress

**Implementation:** Partial (ADR-0016) — no Route 53/ACM this slice (`terraform/modules/dns/` remains a placeholder). LBC IRSA is in `terraform/environments/dev/workload/lbc.tf`. Ingress YAML at `k8s/base/ingress/ingress.yaml` (HTTP-first; do not apply). Helm values at `helm-values/aws-load-balancer-controller.yaml`. `helm install` waits on E-3 apply.

### ACM Certificate

| Parameter | Value |
|-----------|-------|
| Domain | `*.{domain}` (wildcard) — **only if `domain_name` is set and NS are delegated** |
| Validation Method | DNS (Route 53) |
| Region | `eu-central-1` (same as ALB; not us-east-1) |

### Route 53

| Parameter | Value |
|-----------|-------|
| Hosted Zone | `{domain}` as variable; **omit the module when empty** (ADR-0016). $0.50/zone/month only if created. |
| Dev Record | `petclinic-dev.{domain}` → ALB (A record, alias) — **after** LBC creates the ALB (PETPLAT-31) |
| Prod Record | `petclinic.{domain}` → ALB (A record, alias) — skip this epic |

### AWS Load Balancer Controller

| Parameter | Value |
|-----------|-------|
| Installation | Helm chart (`aws-load-balancer-controller` from `eks.amazonaws.com/charts`) — **after E-3 apply** (ADR-0016). Author IAM/values now; do not `helm install` this epic. |
| Namespace | `kube-system` |
| Auth | IRSA in **workload** (OIDC dies with the cluster; see [IRSA Roles](#irsa-roles)) |
| IngressClass | `alb` |

### Ingress Resource

Use `spec.ingressClassName` (the `kubernetes.io/ingress.class` annotation is deprecated on 1.35):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: "{acm-certificate-arn}"   # omit until ACM exists (ADR-0016)
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"                         # omit until ACM exists; HTTP-only until then
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health
    alb.ingress.kubernetes.io/healthcheck-port: "8080"
spec:
  ingressClassName: alb
```

Services stay **ClusterIP**. Do not create NodePorts. LBC `target-type: ip` registers **pod IPs** on container port 8080 (same as saas-ntier-lab). The ALB lives in public subnets; nodes stay private. NetworkPolicy for api-gateway must allow the **public subnet CIDRs** (ALB ENIs), not the VPC CIDR and not NodePort SNAT.

### Ingress Routing

| Path | Backend Service | Port |
|------|-----------------|------|
| `/` | `api-gateway` | 8080 |

All routing to backend services is handled by the API Gateway (Spring Cloud Gateway), not by the ALB Ingress.

---

## Application Services

**Implementation:** Not started — application repo is read-only; no Helm values or cluster workloads yet.

### Service Inventory

| Service | Spring Name | Port | MySQL | Config Server | Discovery | Startup Order |
|---------|-------------|------|-------|---------------|-----------|---------------|
| Config Server | `config-server` | 8888 | No | Self (Git backend) | No | 1st (must be healthy first) |
| Discovery Server | `discovery-server` | 8761 | No | Yes | Self (Eureka) | 2nd (depends on Config) |
| API Gateway | `api-gateway` | 8080 | No | Yes | Yes | 3rd+ |
| Customers Service | `customers-service` | 8081 | Yes | Yes | Yes | 3rd+ (before Visits) |
| Visits Service | `visits-service` | 8082 | Yes | Yes | Yes | After Customers (FK dependency) |
| Vets Service | `vets-service` | 8083 | Yes | Yes | Yes | 3rd+ |
| GenAI Service | `genai-service` | 8084 | Optional | Yes | Yes | 3rd+ |
| Admin Server | `admin-server` | 9090 | No | Yes | Yes | 3rd+ (Spring Boot Admin 3.4.1) |

### Spring Profiles

| Profile | Purpose | When Active |
|---------|---------|-------------|
| `docker` | Changes Config Server URL from `localhost` to `config-server` (Docker DNS) | Set in Dockerfile: `SPRING_PROFILES_ACTIVE=docker` |
| `mysql` | Switches from HSQLDB to MySQL | Added for RDS-backed services: `SPRING_PROFILES_ACTIVE=docker,mysql` |
| `production` | Default active profile for vets-service and genai-service. **Required for vets-service Caffeine cache** — the `CacheConfig` class is gated on `@Profile("production")` so caching only works when this profile is active. | Set in application.yml |
| `chaos-monkey` | Chaos engineering (latency, exceptions) | Optional, testing only |
| `native` | Config Server uses local filesystem instead of Git repo | Config Server only, requires `GIT_REPO` env var |

### Config Server Details

| Parameter | Value |
|-----------|-------|
| Git URI | `https://github.com/spring-petclinic/spring-petclinic-microservices-config` |
| Default Label (branch) | `main` |
| Config Import | All services use `optional:configserver:${CONFIG_SERVER_URL:http://localhost:8888/}` |
| Docker Profile Override | `configserver:http://config-server:8888` |

### API Gateway Routes

| Route ID | Path | Target | Filters |
|----------|------|--------|---------|
| `vets-service` | `/api/vet/**` | `lb://vets-service` | `StripPrefix=2` |
| `visits-service` | `/api/visit/**` | `lb://visits-service` | `StripPrefix=2` |
| `customers-service` | `/api/customer/**` | `lb://customers-service` | `StripPrefix=2` |
| `genai-service` | `/api/genai/**` | `lb://genai-service` | `StripPrefix=2`, CircuitBreaker |

Default filters on all routes: `CircuitBreaker` (with `/fallback` URI), `Retry` (1 retry on `SERVICE_UNAVAILABLE`). Resilience4j `TimeLimiter` is configured with a 10-second timeout.

The API Gateway also serves an **AngularJS frontend** (static files: AngularJS 1.8.3, Bootstrap 5.3.3, Font Awesome 4.7.0) — this is the only user-facing service. All backend service API calls go through the gateway routes above.

### GenAI Service Configuration

| Parameter | Value |
|-----------|-------|
| AI Provider | OpenAI (default) |
| Model | `gpt-4o-mini` |
| Temperature | 0.7 |
| Spring AI Version | `2.0.0-M1` (milestone release) |
| API Key Env Var | `OPENAI_API_KEY` (defaults to `demo` if not set) |
| Alternate Provider | Azure OpenAI (`AZURE_OPENAI_KEY`, `AZURE_OPENAI_ENDPOINT`) |
| Application Type | Reactive (WebFlux) |
| Database | Has JPA + MySQL dependencies but no schema files. Includes `vectorstore.json` (124KB pre-populated vet embeddings for RAG) |
| Config Import Extra | Also imports `optional:classpath:/creds.yaml` (not present by default, used for local credential overrides) |

---

## Kubernetes Manifests

**Implementation:** Partial — Ingress, ExternalSecret, `k8s/base/namespaces.yaml`, and `k8s/base/network-policies/` are in git (ADR-0018). Not applied. Per-service Deployments, Services, ConfigMaps, probes, JDBC, and init containers are the Helm chart (E-16). VPC CNI NetworkPolicy stays PETPLAT-84.

### Namespaces

| Namespace | Environment | PSA Labels |
|-----------|-------------|------------|
| `petclinic-dev` | Dev | `pod-security.kubernetes.io/enforce: baseline`; `warn` and `audit`: `restricted` |
| `petclinic-prod` | Prod | `pod-security.kubernetes.io/enforce: baseline`; `warn` and `audit`: `restricted` |

### Standard Labels (All Resources)

```yaml
app.kubernetes.io/name: "{service-name}"
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/component: "{server|service|gateway|admin}"
```

### Health Probes (All Services)

| Probe | Path | Port | Period | Timeout | Failure Threshold |
|-------|------|------|--------|---------|-------------------|
| Startup | `/actuator/health` | Service port | 10s | 5s | 30 (allows up to 5 min) |
| Readiness | `/actuator/health/readiness` | Service port | 10s | 5s | 3 |
| Liveness | `/actuator/health/liveness` | Service port | 15s | 5s | 3 |

The startupProbe runs first and disables readiness and liveness checks until Spring Boot has fully initialized. Once startup passes, readiness and liveness take over. Config Server uses `/actuator/health` for all three probes.

### Resource Requests and Limits

| Service | CPU Request | CPU Limit | Memory Request | Memory Limit |
|---------|-------------|-----------|----------------|--------------|
| config-server | 100m | 500m | 128Mi | 512Mi |
| discovery-server | 100m | 500m | 128Mi | 512Mi |
| api-gateway | 200m | 1000m | 128Mi | 512Mi |
| customers-service | 100m | 500m | 128Mi | 512Mi |
| visits-service | 100m | 500m | 128Mi | 512Mi |
| vets-service | 100m | 500m | 128Mi | 512Mi |
| genai-service | 100m | 500m | 128Mi | 512Mi |
| admin-server | 100m | 500m | 128Mi | 512Mi |

API Gateway gets higher CPU (200m/1000m) because it handles all incoming traffic routing. Memory requests are set to 128Mi (with 512Mi limit) to fit on t4g.small nodes (2 GiB RAM). Spring Boot services idle around 200-300 MiB — the 512Mi limit provides headroom for spikes.

### Environment Variables per Service

**All services:**

| Variable | Value | Source |
|----------|-------|--------|
| `SPRING_PROFILES_ACTIVE` | `docker` (non-DB) or `docker,mysql` (DB services) | Deployment spec |
| `CONFIG_SERVER_URL` | `http://config-server:8888` | ConfigMap |

**DB services (customers, visits, vets) — additional:**

| Variable | Value | Source |
|----------|-------|--------|
| `SPRING_DATASOURCE_URL` | `jdbc:mysql://{rds-endpoint}:3306/petclinic?sslMode=REQUIRED` | ConfigMap |
| `SPRING_DATASOURCE_USERNAME` | From secret | K8s Secret (ESO) |
| `SPRING_DATASOURCE_PASSWORD` | From secret | K8s Secret (ESO) |

**GenAI service — additional:**

| Variable | Value | Source |
|----------|-------|--------|
| `OPENAI_API_KEY` | From secret | K8s Secret (ESO) |

### Init Containers (Startup Order Enforcement)

Services that depend on Config Server use an init container that waits for Config Server to be healthy:

```yaml
initContainers:
  - name: wait-for-config-server
    image: busybox:1.36
    command: ['sh', '-c', 'until wget -qO- http://config-server:8888/actuator/health; do sleep 5; done']
```

Services that depend on Discovery Server (all except Config Server) add a second init container:

```yaml
  - name: wait-for-discovery-server
    image: busybox:1.36
    command: ['sh', '-c', 'until wget -qO- http://discovery-server:8761/actuator/health; do sleep 5; done']
```

### SecurityContext (All Deployments)

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
containers:
  - securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      readOnlyRootFilesystem: false  # Spring Boot needs /tmp for file uploads and caching
      seccompProfile:
        type: RuntimeDefault
```

### Manifest File Structure

Each service directory contains:

| File | Content |
|------|---------|
| `deployment.yaml` | Deployment with probes, resources, env vars, init containers |
| `service.yaml` | ClusterIP Service exposing the service port |
| `configmap.yaml` | Environment-specific configuration (URLs, non-secret settings) |
| `serviceaccount.yaml` | ServiceAccount (annotated with IRSA role ARN where needed) |

---

## Kubernetes Overlays

**Implementation:** Contract frozen (ADR-0019). The tables below are the requirements for `helm-values/{dev,prod}.yaml`, written in E-16. No `k8s/overlays/`. Not applied. Prod replica and HPA max counts do not fit 2× t4g.small; do not apply them on the learning cluster.

### Dev env values (`helm-values/dev.yaml`)

| Parameter | Value |
|-----------|-------|
| Namespace | `petclinic-dev` |
| Replicas (all services) | 1 |
| Image Tag | Commit SHA (CI updates `helm-values/{service}.yaml`, ArgoCD deploys) |

### Prod env values (`helm-values/prod.yaml`)

| Service | Replicas | Notes |
|---------|----------|-------|
| config-server | 2 | HA for config distribution |
| discovery-server | 2 | HA for service registry |
| api-gateway | 2 | HA, public-facing entry point |
| customers-service | 2 | HA |
| visits-service | 2 | HA |
| vets-service | 2 | HA |
| genai-service | 1 | Lower priority, cost saving |
| admin-server | 1 | Monitoring tool, single replica sufficient |

### Horizontal Pod Autoscaler (Prod only)

| Service | Min | Max | CPU Target |
|---------|-----|-----|------------|
| api-gateway | 2 | 6 | 70% |
| customers-service | 2 | 4 | 70% |
| visits-service | 2 | 4 | 70% |
| vets-service | 2 | 4 | 70% |
| genai-service | 1 | 3 | 70% |

HPA requires Metrics Server (PETPLAT-72, E-14). E-9 does not install it. No HPA for config-server, discovery-server, or admin-server.

### Pod Disruption Budgets (Prod only)

| Service | minAvailable |
|---------|-------------|
| config-server | 1 |
| discovery-server | 1 |
| api-gateway | 1 |
| customers-service | 1 |
| visits-service | 1 |
| vets-service | 1 |

No PDB for genai-service or admin-server. E-16 renders these from `helm-values/prod.yaml`. Dev has PDB off.

### Resource Quotas

Written later as namespace objects in `k8s/base/` (PETPLAT-89, E-13), not as Helm values. Use this table. The larger example numbers on PETPLAT-89 are not the contract.

| Parameter | Dev | Prod |
|-----------|-----|------|
| Max CPU | 4 | 4 |
| Max Memory | 4Gi | 4Gi |
| Max Pods | 30 | 30 |

### Helm Values Structure (replaces Kustomize overlays)

Environment-specific configuration is managed via Helm values files in `helm-values/`:
- `helm-values/dev.yaml` — dev overrides (replicas=1, no HPA, no PDB)
- `helm-values/prod.yaml` — prod replica, HPA, and PDB tables (ADR-0019). genai and admin stay at 1 replica with no PDB.
- Per-service files hold service-specific config (ports, env vars, init containers)
- ArgoCD merges service + environment values when deploying

Namespaces are `k8s/base/namespaces.yaml`. ExternalSecrets are `k8s/base/external-secrets/`. There is no `k8s/overlays/` tree.

---

## CI/CD Pipeline

**Implementation:** Authored (ADR-0020), not applied. OIDC provider and `petclinic-github-actions-role` are in `terraform/environments/dev/network/github_oidc.tf`. `github_repository` must be set in local `terraform.tfvars` before the next network plan. Reference build workflow: `.github/workflow-templates/build-push.yml`. Tag workflow: `.github/workflows/update-image-tags.yml` (inert until E-16). Live build is copied into an application fork. ArgoCD verify waits on E-16 and E-17. PETPLAT-53 and PETPLAT-54 stay deferred.

### Architecture: CI + GitOps

GitHub Actions handles **CI only** (build and push images). **ArgoCD handles CD**. The tag-update workflow does not call AWS. ECR login belongs to the fork build.

| Concern | Tool | How |
|---------|------|-----|
| Build & Push images | GitHub Actions in the **app fork** | Reference `build-push.yml` in this repo; copy into the fork. ARM64, Trivy, push to ECR |
| Update image tags | GitHub Actions in **this repo** | `update-image-tags.yml` on `repository_dispatch` `app-image-built` |
| Deploy to Kubernetes | ArgoCD | Watches Git, detects tag changes, syncs Helm releases |

### Workflows

| Workflow | File | Where it runs | What it does |
|----------|------|--------------|--------------|
| Build & Push | Reference `.github/workflow-templates/build-push.yml`; live copy in the app fork | Push to `main` on the fork | Build changed services only, ARM64, Trivy, push to ECR, dispatch `app-image-built` |
| Update Image Tags | `.github/workflows/update-image-tags.yml` | This repo, `repository_dispatch` | Sets `image.tag` in `helm-values/{service}.yaml` and pushes. Inert until E-16 creates those files. |

> **No deploy workflows.** Prod approval is ArgoCD manual sync, not a GitHub Environment. Third-party actions are pinned to a commit SHA.

The OIDC provider and role are Terraform in **dev/network** (keep), not the destroyable workload and not the EKS IRSA issuer. Apply is a later gate. `{org}/{repo}` in the trust policy comes from gitignored tfvars. Never commit an account ID. `ecr:GetAuthorizationToken` is the only action with `Resource: "*"`. Push, layer upload, and layer read (`BatchGetImage`, `GetDownloadUrlForLayer`) are limited to the `petclinic-dev/{service}` repository ARNs.

### OIDC Federation (No Long-Lived Credentials)

| Parameter | Value |
|-----------|-------|
| OIDC Provider | `token.actions.githubusercontent.com` |
| Audience | `sts.amazonaws.com` |
| Subject Filter | `repo:{org}/{repo}:ref:refs/heads/main` |
| IAM Role | `petclinic-github-actions-role` |
| Permissions | ECR push on the eight `petclinic-dev` repos (`BatchCheckLayerAvailability`, `BatchGetImage`, `GetDownloadUrlForLayer`, layer upload, `PutImage`) plus `ecr:GetAuthorizationToken` on `*` — no S3, no DynamoDB (CI workflows do not run Terraform) |

### GitHub Secrets

| Secret Name | Purpose |
|-------------|---------|
| `AWS_REGION` | `eu-central-1` |
| `AWS_ROLE_ARN` | OIDC role ARN for `aws-actions/configure-aws-credentials` |
| `AWS_ACCOUNT_ID` | AWS account ID (for ECR registry URL) |

### Build Steps (build-push.yml)

1. Checkout application repo
2. Set up JDK 17
3. Set up Docker Buildx + QEMU (for ARM64 cross-compilation)
4. Configure AWS credentials (OIDC)
5. Login to ECR: `aws ecr get-login-password --region eu-central-1`
6. Maven build: `./mvnw clean install -P buildDocker -Dcontainer.platform="linux/arm64"`
7. Trivy scan: fail on CRITICAL CVEs
8. Tag images with commit SHA (short, 7 chars): `${GITHUB_SHA::7}`
9. Push **changed** images to ECR (path filter; not all 8 on every push)

> **ARM cross-compilation:** GitHub Actions runners are x86_64. Building ARM64 images requires QEMU emulation via `docker/setup-qemu-action` and `docker/setup-buildx-action`. Build time increases from ~2 min to ~5 min per image, which is acceptable for a learning project.

### Update Image Tags Steps (update-image-tags.yml)

1. Checkout platform repo
2. Update image tag in `helm-values/{service}.yaml` — only for services in the `repository_dispatch` payload (not all 8 on every run)
3. Git commit + push: `"ci: update image tags to ${SHA} (${service-list})"`

ArgoCD verification of that commit waits until E-16 has created `helm-values/{service}.yaml`, E-17 is installed, and a cluster exists. PETPLAT-53 (reusable workflows) and PETPLAT-54 (live rollback) are deferred.

### Image Tag Update Mechanism

```bash
# Update image tag only for services included in the repository_dispatch payload
SERVICES="${{ github.event.client_payload.services }}"  # e.g. "customers-service vets-service"
SHA="${{ github.event.client_payload.sha }}"

for service in ${SERVICES}; do
  yq -i ".image.tag = \"${SHA}\"" helm-values/${service}.yaml
done

# Commit and push
git add helm-values/
git commit -m "ci: update image tags to ${SHA} (${SERVICES})"
git push
```

---

## Observability

**Implementation:** Partial (ADR-0021). The tainted observability node group is in `terraform/modules/eks/` and wired from `terraform/environments/dev/workload/` with `enable_observability` default **false**. Not applied. Helm values are in `helm-values/observability/` for chart `kube-prometheus-stack` 91.5.0 (dev uses emptyDir; prod file is inventory). Not installed. `terraform/modules/observability/` stays an empty placeholder (no CloudWatch). Live `helm install`, “metrics visible”, and durable EBS wait on a cluster, `enable_observability=true`, and PETPLAT-84. Meaningful scrapes wait on E-16. Loki, FluentBit, and Zipkin (PETPLAT-59, PETPLAT-60) are deferred. Grafana admin password is a Kubernetes Secret at install time, never committed.

Learning subset on that node: Prometheus, Grafana, Alertmanager. Node selector `workload=observability`, toleration `dedicated=observability:NoSchedule`. Before PETPLAT-84, a session may use emptyDir; the PV sizes below stay the contract once the EBS driver exists.

### Prometheus

| Parameter | Dev | Prod |
|-----------|-----|------|
| Namespace | `monitoring` | `monitoring` |
| Scrape Interval | 15s | 15s |
| Evaluation Interval | 15s | 15s |
| Retention | 7 days | 15 days |
| Storage | PersistentVolume (EBS, 10Gi) | PersistentVolume (EBS, 50Gi) |

#### Scrape Targets

| Job Name | Target | Metrics Path | Port |
|----------|--------|-------------|------|
| `config-server` | `config-server.petclinic-{env}:8888` | `/actuator/prometheus` | 8888 |
| `discovery-server` | `discovery-server.petclinic-{env}:8761` | `/actuator/prometheus` | 8761 |
| `api-gateway` | `api-gateway.petclinic-{env}:8080` | `/actuator/prometheus` | 8080 |
| `customers-service` | `customers-service.petclinic-{env}:8081` | `/actuator/prometheus` | 8081 |
| `visits-service` | `visits-service.petclinic-{env}:8082` | `/actuator/prometheus` | 8082 |
| `vets-service` | `vets-service.petclinic-{env}:8083` | `/actuator/prometheus` | 8083 |
| `genai-service` | `genai-service.petclinic-{env}:8084` | `/actuator/prometheus` | 8084 |
| `admin-server` | `admin-server.petclinic-{env}:9090` | `/actuator/prometheus` | 9090 |

### Grafana

| Parameter | Value |
|-----------|-------|
| Namespace | `monitoring` |
| Datasources | Prometheus (auto-configured). Loki when PETPLAT-59 is installed |
| Storage | PersistentVolume (EBS, 5Gi) |
| Admin Credentials | Kubernetes Secret created at install. Never in git |
| Dashboards | JSON in `helm-values/observability/dashboards/`, provisioned via the chart |

#### Dashboard Set

| Dashboard | Key Metrics |
|-----------|-------------|
| Service Overview | All 8 services: up/down status, RPS, error rate |
| Per-Service (x8) | Request rate, error rate, p95/p99 latency |
| JVM Metrics | Heap usage, GC pauses, thread count |

### Alert Rules (Prometheus)

| Alert | Condition | Duration | Severity |
|-------|-----------|----------|----------|
| ServiceDown | `up{job=~"config-server|discovery-server|api-gateway|customers-service|visits-service|vets-service|genai-service|admin-server"} == 0` | 1m | `critical` |
| HighErrorRate | `rate(http_server_requests_seconds_count{status=~"5.."}[5m]) / rate(http_server_requests_seconds_count[5m]) > 0.05` | 5m | `warning` |
| HighLatency | `histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m])) > 0.5` | 5m | `warning` |
| PodRestartLoop | `increase(kube_pod_container_status_restarts_total[15m]) > 3` | 0m | `critical` |
| HighMemoryUsage | `sum by (namespace, pod, container) (container_memory_working_set_bytes{container!="",container!="POD"}) / sum by (namespace, pod, container) (kube_pod_container_resource_limits{resource="memory",container!=""}) > 0.8` | 5m | `warning` |

### Alertmanager

| Parameter | Value |
|-----------|-------|
| Namespace | `monitoring` |
| Notification Channel | Email (minimum), Slack (recommended) |
| Critical Routing | Immediate notification |
| Warning Routing | Batched (5m group interval) |

### FluentBit (Logging)

| Parameter | Dev | Prod |
|-----------|-----|------|
| Deployment | DaemonSet on all nodes | DaemonSet on all nodes |
| Output | Loki (`http://loki.monitoring:3100`) | Loki (`http://loki.monitoring:3100`) |
| Log Labels | `namespace`, `pod`, `container` | `namespace`, `pod`, `container` |
| Auth | None — Loki is in-cluster, no IAM role required |

### Loki (Log Aggregation)

| Parameter | Dev | Prod |
|-----------|-----|------|
| Namespace | `monitoring` | `monitoring` |
| Port | 3100 | 3100 |
| Image | `grafana/loki` | `grafana/loki` |
| Storage | PersistentVolume (EBS, 10Gi) | PersistentVolume (EBS, 50Gi) |
| Log Retention | 7 days | 30 days |

Loki receives logs from FluentBit and exposes them as a Grafana datasource. Log-based alert rules are defined as Loki alerting rules and routed through Alertmanager — same alert pipeline as Prometheus.

#### Loki Alert Rules

| Alert | LogQL Condition | Duration | Severity |
|-------|----------------|----------|----------|
| `LogErrorSpike` | `rate({namespace=~"petclinic-.*"} \|= "ERROR" [5m]) > 0.5` | 5m | `warning` |
| `JVMOutOfMemory` | `count_over_time({namespace=~"petclinic-.*"} \|= "OutOfMemoryError" [5m]) > 0` | 0m | `critical` |

### Zipkin (Tracing)

| Parameter | Value |
|-----------|-------|
| Namespace | `tracing` |
| Port | 9411 |
| Image | `openzipkin/zipkin` |
| Services send traces via | OpenTelemetry exporter (configured in Spring Cloud Config) |

---

## IRSA Roles

**Implementation:** Partial — LBC role `petclinic-{env}-lb-controller-role` and ESO role `petclinic-{env}-eso-role` are authored in **workload** (ADR-0016 / ADR-0017). Helm/ESO install waits on E-3 apply.

Five IAM Roles for Service Accounts, each with OIDC trust policy scoped to a specific Kubernetes ServiceAccount. FluentBit no longer requires an IRSA role — it sends logs to Loki in-cluster.

| Role Name Pattern | K8s ServiceAccount | Namespace | IAM Policy | Used By |
|-------------------|--------------------|-----------|------------|---------|
| `petclinic-{env}-eso-role` | `external-secrets-sa` | `external-secrets` | `secretsmanager:GetSecretValue`, `secretsmanager:DescribeSecret` on `arn:aws:secretsmanager:eu-central-1:{account}:secret:petclinic/*` | ESO |
| `petclinic-{env}-lb-controller-role` | `aws-load-balancer-controller` | `kube-system` | AWS Load Balancer Controller IAM policy (managed) | ALB Controller |
| `petclinic-{env}-ebs-csi-role` | `ebs-csi-controller-sa` | `kube-system` | `AmazonEBSCSIDriverPolicy` (AWS managed) | EBS CSI Driver |
| `petclinic-{env}-argocd-role` | `argocd-server` | `argocd` | Minimal: only needed if ArgoCD accesses AWS resources directly (optional) | ArgoCD |
| `petclinic-{env}-karpenter-role` | `karpenter` | `kube-system` | AWS-documented Karpenter v1 controller policy, scoped with `eks:cluster-name` tag conditions. Do not author a custom `ec2:*` / `sqs:*` on `*`. | Karpenter |

### IRSA Trust Policy Template

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::{account}:oidc-provider/{oidc-provider}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "{oidc-provider}:sub": "system:serviceaccount:{namespace}:{sa-name}",
        "{oidc-provider}:aud": "sts.amazonaws.com"
      }
    }
  }]
}
```

---

## Security Controls

**Implementation:** Partial — state-bucket SSE-S3 + HTTPS-only policy and gitignore/hooks for secrets. RDS TLS is required (ADR-0015). Namespace PSA labels and NetworkPolicy YAML are in git (ADR-0018) and not applied. VPC CNI NetworkPolicy stays PETPLAT-84.

### Encryption Matrix

| Resource | Encryption at Rest | Encryption in Transit | Key |
|----------|-------------------|----------------------|-----|
| RDS MySQL | KMS (AWS default `aws/rds` key) | TLS required (`require_secure_transport=1`; JDBC `sslMode=REQUIRED`) | AWS managed |
| S3 (state bucket) | SSE-S3 (AES256) | HTTPS enforced | AWS managed |
| EBS Volumes | Default encryption enabled | N/A | AWS managed |
| ECR Images | AES256 | HTTPS | AWS managed |
| Secrets Manager | KMS (AWS default `aws/secretsmanager` key) | HTTPS | AWS managed |
| ALB | N/A | TLS at ALB **when ACM exists**; otherwise HTTP only (ADR-0016) | ACM |

### Kubernetes Network Policies

| Policy | Namespace | Effect |
|--------|-----------|--------|
| Default deny ingress | `petclinic-{env}` | Deny all ingress by default |
| Config Server allow | `petclinic-{env}` | Allow ingress to 8888 from all pods in namespace |
| Discovery Server allow | `petclinic-{env}` | Allow ingress to 8761 from all pods in namespace |
| API Gateway allow | `petclinic-{env}` | Allow ingress to 8080 from **public subnet CIDRs** (ALB ENIs, `target-type: ip`). Dev: `10.0.1.0/24` and `10.0.2.0/24`. Not the VPC CIDR (`10.0.0.0/16`). |
| Domain services allow | `petclinic-{env}` | Allow ingress to 8081-8084 from API Gateway pods only |
| Admin Server allow | `petclinic-{env}` | Allow ingress to 9090 from internal only |
| Egress allow | `petclinic-{env}` | Allow egress to Config Server, Discovery, RDS, DNS (53), HTTPS (443) |

### Pod Security Admission

| Namespace | Enforce | Warn | Audit |
|-----------|---------|------|-------|
| `petclinic-dev` | `baseline` | `restricted` | `restricted` |
| `petclinic-prod` | `baseline` | `restricted` | `restricted` |

### Operator access (no extra SKUs)

| Path | How | Cost |
|------|-----|------|
| kubectl | EKS API public+private, `public_access_cidrs` = `my_ip` `/32` (CLI `-var`, never tfvars) | included in EKS control plane |
| Host debug (kubelet, CNI, disk) | SSM Session Manager on EKS nodes (`AmazonSSMManagedInstanceCore`) | $0; uses NAT to public SSM endpoints while the learning stack is up |
| NAT repair | SSM on the NAT instance only (iptables) | $0 |
| RDS from laptop | Optional SSM port-forward via a node (nodes already allow 3306) | $0 |
| SSH / bastion | Not used | — |
| SSM / ECR / STS interface VPCEs | Not used (budget) | — |

SSM does not work with the network stack alone (no instances, no NAT).

### Checkov (PETPLAT-66)

Scan Terraform with Checkov 3.2.484 (`.checkov.yaml` + `./scripts/checkov.sh`). Global skips are budget/learning-account checks (VPC Flow Logs, IAM permissions boundary, EC2 detailed monitoring, EBS optimized on `t4g.micro`). Resource skips are `# checkov:skip=` comments: ALB HTTP `0.0.0.0/0` (ADR-0001), NAT public IP, and keep-stack SGs that attach when EKS/RDS/ALB land. Install once: `python3 -m venv .venv && .venv/bin/pip install -r requirements-checkov.txt`.

### Operator IP (`my_ip`)

Same habit as saas-ntier-lab. The laptop public IP changes every connection. **Do not** put it in `terraform.tfvars`. Pass it on every **workload** `plan` / `apply`:

```bash
-var="my_ip=$(curl -s https://checkip.amazonaws.com)/32"
```

The same `-var` is **accepted but unused** on **network** (VPC + ECR) so one CLI works in both roots. After a reconnect, apply **workload** again with a fresh curl — that is what updates the EKS API allow-list. Do not open `0.0.0.0/0`. The Petclinic ALB stays 80/443 from the internet (unlike the saas lab HTTP ALB, which is also `/32`).

---

## Scaling and Cost

**Implementation:** Not started — cost table is documentation only. `scripts/start-env.sh` / `stop-env.sh` exist but target EKS/RDS that are not deployed. No budgets or Karpenter.

### Monthly Cost Estimate (Free Tier Optimized)

This is a learning project. Instance choices maximize AWS free tier eligibility.

| Resource | Dev (~) | Prod (~) | Free Tier |
|----------|---------|----------|-----------|
| EKS Control Plane | $73 | $73 | None — unavoidable cost |
| EC2 Nodes (2x t4g.small) | $0 | $0 | Graviton free trial (750 hrs/mo until Dec 2026) |
| Observability node (1x t4g.large) | $0 unless `-var=enable_observability=true`, then **$0.0768/h** | not wired | ADR-0021. Apply again without the flag to delete it. Not in the free-trial t4g.small allowance |
| RDS MySQL (db.t4g.micro) | ~$0 session / **~$0.019/h** OnDemand | same | Free-tier hours are an allowance, not “$0 if left on.” Destroy with workload (ADR-0015). |
| ALB | ~$0 session / **~$0.027/h** + LCU | same | Created by LBC after Ingress apply; destroy with cluster (ADR-0016). Do not treat 24/7 as $0. |
| S3 + DynamoDB (state) | ~$0 | ~$0 | SSE-S3 + PAY_PER_REQUEST; no CMK |
| ECR Storage | ~$1 | ~$1 | 500 MB free, then $0.10/GB/month |
| EBS (PVs — Prometheus, Grafana, Loki) | $2 | $2 | 30 GB gp3 |
| Route 53 | $0 or $0.50 | same | $0.50/zone **only if `domain_name` is set** (ADR-0016). Skip until a delegated domain exists. |
| Secrets Manager | $0 after destroy; **$0.40** per secret while workload is up | same | RDS secret when RDS exists (ADR-0015). OpenAI **only** if `openai_api_key` is set (ADR-0017). No git-cred secrets. Keep-stack SM is $0. |
| Data Transfer | $1 | $1 | 100 GB/mo free |
| NAT instance (`t4g.micro`) | $0 session / ~$7 if left on | same | Destroy with EKS; not NAT Gateway |
| **Total if left 24/7** | **~$80–87/mo** | **~$80–87/mo** | EKS control plane is the main cost |
| **Total with destroy-after-session** | **~$5–9/mo** | do not run | Network ~$0 idle + EKS $0.10/hr while up |

> **Destroy the learning stack after each session** (NAT, EKS, nodes, RDS, ALB) and keep the network stack. EKS has no stop: $0.10/hr for as long as the cluster exists. At 10 hours/week that is ~$4–5/month for the control plane (plus NAT ~$0.01/hr while up). Target: **entire course under $20 AWS spend** — a usage cap, not a 24/7 monthly bill. Do not leave EKS overnight. Do not run prod for day-to-day learning.

Always-on network (VPC, subnets, IGW, S3 gateway) is ~$0. NAT instance is **~$7/month only if left on** — it belongs in the destroyable stack. No NAT Gateway (~$38–76/month avoided). No interface VPCEs. SSM Session Manager is $0 (uses NAT to reach public SSM APIs during a session). No customer KMS CMK (ADR-0012).

### Spot Instance Configuration (Dev — Optional)

| Parameter | Value |
|-----------|-------|
| Instance Types (mixed) | `t4g.small`, `t4g.medium` |
| Capacity Type | `SPOT` (with on-demand fallback) |
| Savings | ~60-70% on compute (when free trial expires) |

> **Note:** While the Graviton free trial is active, spot instances provide no cost benefit. This configuration is documented for when the free trial expires or for production use with larger instances.

### Budget Alerts

| Environment | Monthly Budget | Alert at |
|-------------|---------------|----------|
| Dev | $100 | 50%, 80%, 100% |
| Prod | $100 | 50%, 80%, 100% |
| Notification | Email to configurable address | — |

---

## Docker Build

**Implementation:** Not started — no CI image build.

### Build Command

```bash
# Build all 8 Docker images for ARM64 (required for t4g Graviton nodes)
./mvnw clean install -P buildDocker -Dcontainer.platform="linux/arm64"
```

> **Important:** EKS nodes are ARM64 (Graviton). All Docker images MUST be built for `linux/arm64`. The base image `eclipse-temurin:17` supports multi-arch. Local builds on Apple Silicon (M1/M2/M3) produce ARM images natively. CI/CD builds on x86 GitHub Actions runners require `docker buildx` with QEMU emulation (see [CI/CD Pipeline](#cicd-pipeline)).

### Dockerfile Details

| Parameter | Value |
|-----------|-------|
| Dockerfile Location | `docker/Dockerfile` (shared by all services) |
| Base Image | `eclipse-temurin:17` |
| Build Strategy | Multi-stage (builder + runtime) |
| Layer Extraction | `java -Djarmode=layertools -jar application.jar extract` |
| Layers | `dependencies/`, `spring-boot-loader/`, `snapshot-dependencies/`, `application/` |
| Entrypoint | `java org.springframework.boot.loader.launch.JarLauncher` |
| Build Args | `ARTIFACT_NAME` (JAR name), `EXPOSED_PORT` (service port) |
| Default Profile | `SPRING_PROFILES_ACTIVE=docker` (ENV in Dockerfile) |
| Target Platform | `linux/arm64` (for Graviton t4g nodes) |
| Memory Limit | 512M (set in Docker Compose, enforce in K8s) |
| Local Image Prefix | `springcommunity/` (from Maven pom.xml, e.g., `springcommunity/spring-petclinic-api-gateway`) |

> **Note:** The Maven build produces images with the `springcommunity/` prefix (e.g., `springcommunity/spring-petclinic-customers-service`). The CI/CD pipeline re-tags and pushes to ECR using the `petclinic-{env}/{service}` naming convention.

> **Warning:** The `docker.image.exposed.port` property in each service's pom.xml is a build-time metadata value for the Dockerfile `EXPOSE` directive. Several services have **incorrect values** (copy-paste from template): API Gateway, Visits, Vets, and GenAI all show `8081` in their pom.xml. The actual runtime ports come from the Config Server's Git repository, not from this property. Do NOT rely on pom.xml exposed ports — use the Service Inventory table above.

### Artifact-to-Image Mapping

| Maven Module | JAR Artifact | ECR Repository |
|--------------|-------------|----------------|
| `spring-petclinic-config-server` | `spring-petclinic-config-server-*.jar` | `petclinic-{env}/config-server` |
| `spring-petclinic-discovery-server` | `spring-petclinic-discovery-server-*.jar` | `petclinic-{env}/discovery-server` |
| `spring-petclinic-api-gateway` | `spring-petclinic-api-gateway-*.jar` | `petclinic-{env}/api-gateway` |
| `spring-petclinic-customers-service` | `spring-petclinic-customers-service-*.jar` | `petclinic-{env}/customers-service` |
| `spring-petclinic-visits-service` | `spring-petclinic-visits-service-*.jar` | `petclinic-{env}/visits-service` |
| `spring-petclinic-vets-service` | `spring-petclinic-vets-service-*.jar` | `petclinic-{env}/vets-service` |
| `spring-petclinic-genai-service` | `spring-petclinic-genai-service-*.jar` | `petclinic-{env}/genai-service` |
| `spring-petclinic-admin-server` | `spring-petclinic-admin-server-*.jar` | `petclinic-{env}/admin-server` |

---

## Terraform Modules

**Implementation:** Slice 1 done for `vpc` and `nat`. EKS module is implemented and called from **dev/workload** (ADR-0013). ECR is implemented and called from **dev/network** (ADR-0014). RDS is implemented and called from **dev/workload** (ADR-0015). DNS module remains a stub (ADR-0016, deferred). Secrets module is implemented and called from **dev/workload** (ADR-0017). `observability` remains a stub (ADR-0021; the node group lives in the EKS module). No `karpenter` module yet.

### Module: `vpc`

**Path:** `terraform/modules/vpc/`

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | `"petclinic"` |
| `environment` | string | Environment (dev/prod) | — |
| `vpc_cidr` | string | VPC CIDR block | — |
| `public_subnet_cidrs` | list(string) | Public subnet CIDRs | — |
| `private_subnet_cidrs` | list(string) | Private subnet CIDRs (nodes, RDS) | — |
| `availability_zones` | list(string) | AZs for subnets | — |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `vpc_id` | string | VPC ID |
| `public_subnet_ids` | list(string) | Public subnet IDs (ALB, NAT instance) |
| `private_subnet_ids` | list(string) | Private subnet IDs (nodes, RDS) |
| `private_route_table_ids` | list(string) | Private route tables (workload adds NAT `0.0.0.0/0`) |
| `vpc_cidr` | string | VPC CIDR |
| `eks_cluster_sg_id` | string | EKS cluster security group ID |
| `eks_node_sg_id` | string | EKS node security group ID |
| `rds_sg_id` | string | RDS security group ID |
| `alb_sg_id` | string | ALB security group ID |

### Module: `nat`

**Path:** `terraform/modules/nat/`

Destroyable learning stack. Single `t4g.micro` NAT instance (no NAT Gateway). Called from `terraform/environments/{env}/workload/`.

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | `"petclinic"` |
| `environment` | string | Environment | — |
| `vpc_id` | string | VPC ID | — |
| `vpc_cidr` | string | VPC CIDR for iptables FORWARD/MASQUERADE | — |
| `client_security_group_ids` | list(string) | SGs allowed to NAT (EKS node SG) | — |
| `public_subnet_ids` | list(string) | Public subnets; instance in index 0 | — |
| `instance_type` | string | NAT instance type | `"t4g.micro"` |
| `enable_ssm` | bool | SSM instance profile | `true` |
| `ami_id` | string | Optional AL2023 ARM AMI | `""` |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `instance_id` | string | NAT instance ID |
| `network_interface_id` | string | Primary ENI for private default routes |
| `security_group_id` | string | NAT SG |
| `public_ip` | string | Elastic IP |

### Module: `eks`

**Path:** `terraform/modules/eks/`

Called from `terraform/environments/dev/workload/` (ADR-0013). Node `subnet_ids` are **private**. `api_allowed_cidrs` from `my_ip` (`/32`) at apply — never tfvars. Prod is not wired this epic.

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | `"petclinic"` |
| `environment` | string | Environment | — |
| `cluster_version` | string | Kubernetes version | `"1.35"` |
| `subnet_ids` | list(string) | Private subnet IDs for cluster and nodes | — |
| `cluster_log_retention_days` | number | CloudWatch retention for control-plane logs | `7` |
| `cluster_sg_id` | string | Cluster security group ID | — |
| `node_sg_id` | string | Node security group ID | — |
| `node_instance_types` | list(string) | Instance types for nodes | `["t4g.small"]` |
| `node_ami_type` | string | AMI type for nodes | `"AL2023_ARM_64_STANDARD"` |
| `node_min_size` | number | Min node count | `2` |
| `node_max_size` | number | Max node count | `4` |
| `node_desired_size` | number | Desired node count | `2` |
| `node_disk_size` | number | Disk size in GB | `20` |
| `api_allowed_cidrs` | list(string) | CIDRs allowed to call the public EKS API (operator `/32`) | — (required) |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `cluster_name` | string | EKS cluster name |
| `cluster_endpoint` | string | EKS API endpoint |
| `cluster_ca_certificate` | string | Cluster CA certificate (base64) |
| `oidc_provider_arn` | string | OIDC provider ARN |
| `oidc_provider_url` | string | OIDC provider URL |
| `node_group_name` | string | Managed node group name |
| `node_role_arn` | string | Node IAM role ARN |
| `update_kubeconfig` | string | `aws eks update-kubeconfig` command |

### Module: `ecr`

**Path:** `terraform/modules/ecr/`

Called from `terraform/environments/dev/network/` (ADR-0014). Dev: `image_tag_mutability = MUTABLE`. Prod later: `environments/prod/network`, `IMMUTABLE`. Not wired this epic.

Uses `aws_ecr_repository` with lifecycle policies, scan-on-push, and configurable tag immutability.

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | `"petclinic"` |
| `environment` | string | Environment | — |
| `service_names` | list(string) | Service names for repos | — |
| `image_tag_mutability` | string | Tag mutability | `"MUTABLE"` |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `repository_urls` | map(string) | Map of service_name → ECR repository URL |
| `repository_arns` | map(string) | Map of service_name → ECR repository ARN |

> **Note:** ECR repos are created per environment (`petclinic-dev/`, `petclinic-prod/`). Tag mutability is MUTABLE for dev, IMMUTABLE for prod.

### Module: `rds`

**Path:** `terraform/modules/rds/`

Called from `terraform/environments/dev/workload/` (ADR-0015). Attach the **existing** VPC `rds_sg_id`; do not create a second RDS SG. Password is generated in-module (`random_password`), not a variable. `max_allocated_storage` equal to allocated storage is sent to AWS as `0` (autoscaling off). Prod is not wired this epic.

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | `"petclinic"` |
| `environment` | string | Environment | — |
| `subnet_ids` | list(string) | Subnet IDs for DB subnet group | — |
| `security_group_id` | string | RDS security group ID | — |
| `instance_class` | string | RDS instance class | `"db.t4g.micro"` |
| `allocated_storage` | number | Initial storage in GB | `20` |
| `max_allocated_storage` | number | Max autoscale storage in GB | `20` |
| `multi_az` | bool | Multi-AZ deployment | `false` |
| `backup_retention_period` | number | Backup retention in days | `7` |
| `skip_final_snapshot` | bool | Skip final snapshot on delete | `true` |
| `deletion_protection` | bool | Deletion protection | `false` |
| `kms_key_id` | string | Omit so RDS uses AWS-managed `aws/rds`. Do not create a customer CMK. | `null` |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `endpoint` | string | RDS endpoint hostname |
| `port` | number | RDS port (3306) |
| `db_instance_id` | string | RDS instance ID |
| `secret_arn` | string | Secrets Manager secret ARN for RDS credentials |

### Module: `dns`

**Path:** `terraform/modules/dns/`

Called from `terraform/environments/dev/network/` only when `domain_name` is non-empty (ADR-0016). Empty string → `count = 0`. Do not create a placeholder zone. ACM in **eu-central-1**. Alias to ALB is PETPLAT-31 (needs a live ALB).

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `domain_name` | string | Public domain; empty skips the module | `""` |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `zone_id` | string | Route 53 hosted zone ID |
| `name_servers` | list(string) | NS records for delegation |
| `certificate_arn` | string | ACM certificate ARN |

### Module: `secrets`

**Path:** `terraform/modules/secrets/`

Called from `terraform/environments/dev/workload/` (ADR-0017). Create `petclinic/{env}/openai-api-key` only when `openai_api_key` is non-empty. Skip git credentials. `recovery_window_in_days = 0`. ESO IRSA is **not** in this module — workload `eso.tf` (OIDC from EKS).

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | `"petclinic"` |
| `environment` | string | Environment | — |
| `openai_api_key` | string | OpenAI API key; empty skips the secret | `""` (sensitive) |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `openai_secret_arn` | string | Secrets Manager ARN, empty when skipped |

Note: RDS credentials are NOT managed by this module — they are in the `rds` module (PETPLAT-23).

### Module: `karpenter`

**Path:** `terraform/modules/karpenter/`

Provisions the IAM roles, SQS queue, and EventBridge rules needed for Karpenter.

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | `"petclinic"` |
| `environment` | string | Environment | — |
| `cluster_name` | string | EKS cluster name | — |
| `oidc_provider_arn` | string | OIDC provider ARN (for IRSA) | — |
| `node_role_arn` | string | Node IAM role ARN (for Karpenter-managed nodes) | — |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `karpenter_role_arn` | string | Karpenter controller IRSA role ARN |
| `karpenter_queue_name` | string | SQS interruption queue name |
| `karpenter_instance_profile_name` | string | Instance profile for Karpenter-launched nodes |

## Helm Charts

**Implementation:** Not started — no `helm/` or `helm-values/`.

### Architecture Decision

Helm replaces plain K8s YAML + Kustomize overlays. A **single generic chart** (`helm/petclinic-service/`) is shared by all 8 services. Per-service and per-environment configuration is in `helm-values/`. See [ADR-0007](#adr-index). Workload packaging deferred from E-8 (Deployments, probes, JDBC, init containers) lives in this chart ([ADR-0018](./adr/ADR-0018-e8-namespaces-network-policies.md)). Replica, HPA, and PDB numbers are the E-9 contract ([ADR-0019](./adr/ADR-0019-e9-helm-values-not-overlays.md)), rendered here as `helm-values/{dev,prod}.yaml`.

### Chart Structure

```
helm/
└── petclinic-service/
    ├── Chart.yaml              # name: petclinic-service, version: 0.1.0
    ├── values.yaml             # Defaults (common to all services)
    └── templates/
        ├── deployment.yaml     # Deployment with probes, resources, env vars, init containers
        ├── service.yaml        # ClusterIP Service
        ├── configmap.yaml      # Non-secret configuration
        ├── serviceaccount.yaml # ServiceAccount with IRSA annotation
        ├── hpa.yaml            # HPA (conditional on .Values.autoscaling.enabled)
        ├── pdb.yaml            # PDB (conditional on .Values.podDisruptionBudget.enabled)
        └── _helpers.tpl        # Template helpers (labels, names, selectors)
```

### values.yaml Defaults

```yaml
replicaCount: 1
image:
  repository: ""   # Set per-service: {account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/{service}
  tag: ""          # CI sets a commit SHA. Never latest.
  pullPolicy: IfNotPresent

service:
  port: 8080       # Overridden per-service

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

probes:
  readiness:
    path: /actuator/health/readiness
    initialDelaySeconds: 30
    periodSeconds: 10
  liveness:
    path: /actuator/health/liveness
    initialDelaySeconds: 60
    periodSeconds: 15

env: []              # Additional env vars (set per-service)
initContainers: []   # Wait-for containers (set per-service)

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 4
  targetCPUUtilizationPercentage: 70

podDisruptionBudget:
  enabled: false
  minAvailable: 1

securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
```

### Per-Service Values (`helm-values/`)

```
helm-values/
├── config-server.yaml         # port: 8888, no init containers, no MySQL
├── discovery-server.yaml      # port: 8761, wait-for-config init container
├── api-gateway.yaml           # port: 8080, higher CPU (200m/1000m)
├── customers-service.yaml     # port: 8081, MySQL env vars, wait-for inits
├── visits-service.yaml        # port: 8082, MySQL env vars, wait-for inits
├── vets-service.yaml          # port: 8083, MySQL env vars, wait-for inits
├── genai-service.yaml         # port: 8084, OPENAI_API_KEY env var
├── admin-server.yaml          # port: 9090
├── dev.yaml                   # Dev overrides: replicas=1, no HPA, no PDB
└── prod.yaml                  # Prod overrides: replicas=2, HPA enabled, PDB enabled
```

### Helm Install / Upgrade Command

```bash
# Deploy a service (example: customers-service to dev)
helm upgrade --install customers-service helm/petclinic-service/ \
  -n petclinic-dev \
  -f helm-values/customers-service.yaml \
  -f helm-values/dev.yaml \
  --set image.tag=${SHA}
```

ArgoCD automates this — see [GitOps with ArgoCD](#gitops-with-argocd).

---

## GitOps with ArgoCD

**Implementation:** Not started.

### Architecture Decision

ArgoCD handles all deployments (CD). GitHub Actions is CI-only (build, push, commit image tags). ArgoCD watches the Git repo and syncs automatically (dev) or after manual approval (prod). See [ADR-0008](#adr-index).

### ArgoCD Installation

| Parameter | Value |
|-----------|-------|
| Namespace | `argocd` |
| Installation | `kubectl apply -n argocd -f k8s/argocd/install/` |
| Version | Latest stable (pinned in install manifests) |
| Access | `kubectl port-forward svc/argocd-server -n argocd 8443:443` |
| Admin password | Auto-generated, stored in `argocd-initial-admin-secret` |

### Application CRDs

Each service gets an ArgoCD `Application` CRD per environment:

```
k8s/argocd/applications/
├── dev/
│   ├── config-server.yaml
│   ├── discovery-server.yaml
│   ├── api-gateway.yaml
│   ├── customers-service.yaml
│   ├── visits-service.yaml
│   ├── vets-service.yaml
│   ├── genai-service.yaml
│   └── admin-server.yaml
└── prod/
    └── (same 8 files, different sync policy)
```

### Application CRD Template

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: "{service}-{env}"
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/{your-username}/petclinic-platform.git
    targetRevision: main
    path: helm/petclinic-service
    helm:
      valueFiles:
        - ../../helm-values/{service}.yaml
        - ../../helm-values/{env}.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: "petclinic-{env}"
  syncPolicy:
    automated:           # Dev: auto-sync
      prune: true
      selfHeal: true
    # Prod: remove automated block, require manual sync
```

### Sync Policies

| Environment | Auto-Sync | Prune | Self-Heal | Manual Approval |
|-------------|-----------|-------|-----------|-----------------|
| Dev | Yes | Yes | Yes | No |
| Prod | No | No | No | Yes (via ArgoCD UI/CLI) |

### GitOps Flow

```
Developer pushes code → GitHub Actions builds + pushes ARM64 images to ECR
  → GitHub Actions commits image tag to helm-values/{service}.yaml
    → ArgoCD detects Git change
      → Dev: auto-syncs immediately
      → Prod: queues sync, requires manual approval in ArgoCD UI
```

---

## Karpenter (Node Autoscaling)

**Implementation:** Not started.

### Architecture Decision

Karpenter replaces Cluster Autoscaler. It provisions nodes directly via EC2 Fleet API (faster scaling, better Spot diversification). See [ADR-0009](#adr-index).

### Prerequisites (Terraform)

| Resource | Purpose |
|----------|---------|
| Karpenter Controller IRSA Role | Permissions to manage EC2 instances |
| SQS Queue | Receives EC2 Spot interruption notices |
| EventBridge Rules | Routes Spot interruption, rebalance, and health events to SQS |
| Instance Profile | Attached to Karpenter-launched nodes |

### Karpenter Installation

| Parameter | Value |
|-----------|-------|
| Namespace | `kube-system` |
| Installation | Helm chart: `oci://public.ecr.aws/karpenter/karpenter` |
| ServiceAccount | `karpenter` (annotated with IRSA role) |

### NodePool (Kubernetes CRD)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]       # Use "spot" + "on-demand" when free trial expires
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t4g.small", "t4g.medium"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
  limits:
    cpu: "8"
    memory: "16Gi"
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
```

### EC2NodeClass (Kubernetes CRD)

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest
  subnetSelectorTerms:
    - tags:
        kubernetes.io/cluster/petclinic-{env}: "shared"
  securityGroupSelectorTerms:
    - tags:
        Name: "petclinic-{env}-node-sg"
  instanceProfile: "petclinic-{env}-karpenter-node-profile"
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 20Gi
        volumeType: gp3
```

> **Note:** When the Graviton free trial is active, use `on-demand` only. After expiry, add `spot` to `capacity-type` for cost savings. Karpenter's Spot diversification picks the cheapest available instance type.

---

## ADR Index

**Implementation:** Partial — decisions are recorded in this table. Written files: ADR-0001, ADR-0012, ADR-0013, ADR-0014, ADR-0015, ADR-0016, ADR-0017, ADR-0018, ADR-0019, ADR-0020, ADR-0021. Remaining rows are index-only until E-15.

Architecture Decision Records are stored in `docs/adr/`.

| ADR | Title | Status | Summary |
|-----|-------|--------|---------|
| ADR-0001 | Private EKS nodes with t4g.micro NAT instance | Accepted | Public subnets for ALB + NAT instance only. Nodes and RDS private. S3 gateway endpoint. No NAT Gateway. No interface VPCEs. Network stack stays; learning stack (including NAT) destroyed after each session. SSM Session Manager on nodes/NAT (no bastion). ~$7/mo NAT only if left on vs ~$38–76 NAT GW. |
| ADR-0002 | EKS over ECS | Accepted | EKS chosen for industry relevance and Kubernetes learning. ECS would be simpler but less transferable. |
| ADR-0003 | Shared RDS instance for all services | Accepted | Single `petclinic` database shared by 3 services. Matches app design (FK constraints cross-service). Simpler ops, lower cost. |
| ADR-0004 | Plain K8s YAML over Helm | Superseded by ADR-0007 | Originally chose Kustomize for transparency. Superseded by Helm for industry relevance. |
| ADR-0005 | GitHub Actions with OIDC federation | Accepted | No long-lived AWS credentials. OIDC federation is the AWS-recommended pattern. GitHub Actions for CI. |
| ADR-0006 | Single-AZ RDS for both environments | Accepted | Cost optimization for learning. Multi-AZ doubles RDS cost. Students learn when to enable it. |
| ADR-0007 | Helm over plain K8s YAML | Accepted | Generic Helm chart shared across 8 services. Per-service values files. Industry-standard packaging. Enables ArgoCD GitOps. Trade-off: Helm templating is less transparent than raw YAML. |
| ADR-0008 | ArgoCD for GitOps (CD) | Accepted | ArgoCD watches Git, syncs Helm releases. CI (GitHub Actions) pushes images and commits tags. CD is fully declarative. Dev auto-syncs, prod requires manual approval. |
| ADR-0009 | Karpenter over Cluster Autoscaler | Accepted | Faster node provisioning, better Spot diversification, EC2 Fleet API. Industry trend replacing CAS. Trade-off: more complex IAM setup. |
| ADR-0010 | ECR Private (production-correct pattern) | Accepted | Private ECR teaches the production pattern: IAM-controlled access, lifecycle policies, scan-on-push, tag immutability. Cost: ~$1/month — negligible. |
| ADR-0011 | Secrets Manager for secrets storage | Accepted | Industry-standard secrets management ($0.40/secret/month, ~$1.20 total). Built-in rotation capability, fine-grained IAM. Teaches students the production-grade approach. |
| ADR-0012 | AWS-managed encryption for state and RDS | Accepted | State bucket SSE-S3 (AES256). RDS uses `aws/rds`. No customer CMK. Drops ~$1/month. |
| ADR-0013 | EKS control plane in the destroyable workload | Accepted | Dev EKS + MNG + OIDC + Access Entries in `environments/dev/workload` with NAT, not network. API `my_ip` `/32`. Auth `API`. E-3 uses default add-ons; PETPLAT-84 pins + EBS CSI. Skip prod this epic. |
| ADR-0014 | ECR private repositories in the keep-stack network root | Accepted | Dev ECR in `environments/dev/network`, not workload. Private, scan-on-push, AES256. ~$1/mo. Skip prod. Apply is a later gate. ADR-0010 (private vs public) unchanged. |
| ADR-0015 | RDS MySQL and credentials in the destroyable workload | Accepted | Dev MySQL 8.4 + `petclinic/{env}/rds-credentials` in `environments/dev/workload`, not network. Existing RDS SG. `random_password` in-module. Skip apply and prod this epic. ADR-0003 / 0006 unchanged. |
| ADR-0016 | Skip Route 53/ACM without a domain; LBC waits on EKS | Accepted | Domain optional; gated dns module in network. Learning HTTP to ALB DNS. LBC IRSA in workload; Helm/Ingress apply wait on E-3. Skip placeholder zones. |
| ADR-0017 | Non-RDS secrets and ESO IRSA in the destroyable workload | Accepted | OpenAI SM secret gated in `environments/dev/workload`. ESO IRSA in workload. Skip git creds. YAML now; ESO install waits on E-3. Skip apply and prod. |
| ADR-0018 | E-8 is namespaces and NetworkPolicies only | Accepted | `k8s/base/namespaces.yaml` + `k8s/base/network-policies/`. API gateway ingress from public subnet CIDRs. PETPLAT-39–44 workloads are Helm (E-16). No Kustomize. No apply. |
| ADR-0019 | E-9 freezes the env contract for Helm values | Accepted | Replica, HPA, and PDB numbers for `helm-values/{dev,prod}.yaml` (E-16). No `k8s/overlays/`. No apply. PETPLAT-48 deferred. Prod counts do not fit 2× t4g.small. |
| ADR-0020 | E-10 CI: OIDC in keep network; fork builds; platform updates tags | Accepted | `petclinic-github-actions-role` in `environments/dev/network`. Reference `build-push.yml` copied into an app fork. `update-image-tags.yml` in this repo. No apply. PETPLAT-53 and PETPLAT-54 deferred. |
| ADR-0021 | E-11 observability on a gated t4g.large node group | Accepted | Prometheus, Grafana, and Alertmanager on `petclinic-{env}-observability` only when `enable_observability=true` (default false). Helm values are in `helm-values/observability/` (chart 91.5.0). Not installed. No CloudWatch module. PETPLAT-59 and PETPLAT-60 deferred. Not applied. |
