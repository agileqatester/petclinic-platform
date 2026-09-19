# Petclinic Platform — Cursor Agent Instructions

This repo contains ALL infrastructure code for deploying Spring Petclinic Microservices to AWS.
The application repo (spring-petclinic-microservices) is READ-ONLY — never modify it.

How we use agents vs the frozen spec: [`docs/ai-sdlc.md`](docs/ai-sdlc.md). Open `petclinic.code-workspace` so sibling knowledge folders are in the window.

## Knowledge bases (read-only, not copied)

These are **sibling clones** (`../` from this repo). Never write, commit, or copy them into petclinic.

| Local folder | What to read |
|--------------|----------------|
| `../aidlc-workflows` | AWS AI-DLC. Architect: `core/agents/aidlc-architect-agent.md`. Guide: `docs/guide/`. Do not run the Cursor installer into this repo. |
| `../saas-ntier-lab` | Private EKS nodes, `t4g.micro` NAT instance (`modules/nat/`), S3 gateway endpoint. Preferred network pattern vs all-public IGW when it fits the budget. |
| `../ntier-app` | Private lab and interview docs. Same family as saas. Never commit its content here. |

In chat, `@aidlc-workflows` / `@saas-ntier-lab` after the workspace is open. `docs/technical-spec.md` is the course contract; **accepted ADR-0001** overrides the old all-public crossword (private nodes + `t4g.micro` NAT instance in the destroyable stack). Implementers follow the spec as updated by that ADR.

**Human gates:** you approve every stage (architecture → plan → code → review → terraform plan → apply). See `docs/ai-sdlc.md` and `.cursor/rules/human-gates.mdc`. Do not chain stages unless the user explicitly proceeds.

## AWS CLI

Use profile `petclinic` (`eu-central-1`). Never use `default` (us-east-1) in this repo.

Integrated terminals load this from `.vscode/settings.json`. MCP loads it from `.cursor/mcp.json`. For Agent shell commands, set `AWS_PROFILE=petclinic` if it is not already in the environment.

## Directory Layout

```
terraform/environments/{dev,prod}/{network,workload}/  # Keep VPC vs destroy NAT/EKS
terraform/modules/{vpc,nat,eks,ecr,rds,dns,secrets,observability,karpenter}/
helm/petclinic-service/              # Generic Helm chart (shared by all 8 services)
helm-values/                         # Per-service YAML + per-env (dev.yaml, prod.yaml)
k8s/base/                            # Namespaces, network policies, external-secrets CRs
k8s/argocd/install/                  # ArgoCD installation manifests
k8s/argocd/applications/{dev,prod}/  # ArgoCD Application CRDs
.github/workflows/                   # CI pipelines (build + push only, ArgoCD handles CD)
.cursor/                             # Cursor rules, agents, skills, hooks, MCP
scripts/                             # Operational scripts
docs/                                # Architecture docs, runbooks, ADRs, spec, backlog
```

Those Terraform / Helm / K8s / workflow paths are **story outputs**. They do not exist until the matching Jira epic is implemented. Do not invent a parallel layout.

## Terraform Conventions

- **Provider:** AWS provider ~> 6.0, region eu-central-1
- **Terraform:** >= 1.6.0
- **ECR:** `aws_ecr_repository` in eu-central-1 with lifecycle policies, scan-on-push, and configurable tag immutability
- **State:** S3 + DynamoDB locking, SSE-S3 (AES256). No customer CMK. RDS uses the AWS-managed `aws/rds` key (omit `kms_key_id`). Keys: `petclinic/{env}/network/terraform.tfstate` and `petclinic/{env}/workload/terraform.tfstate`.
- **Modules:** All reusable modules in `terraform/modules/`. Environments call modules.
- **Naming:** `petclinic-{env}-{resource}` (e.g., `petclinic-dev-vpc`, `petclinic-prod-eks`)
- **Tagging:** Every resource MUST have tags: `Project=petclinic`, `Environment={dev|prod}`, `ManagedBy=terraform`
- **Variables:** Use `variable` blocks with `description`, `type`, and `default` where sensible
- **Outputs:** Export IDs, ARNs, and endpoints needed by downstream modules
- **Sensitive values:** Never hardcode secrets. Use `sensitive = true` for secret outputs.
- **Formatting:** Run `terraform fmt` before committing. Use `terraform validate` after edits.
- **Files per module:** `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` (provider constraints)

## Kubernetes Conventions

- **Version:** EKS 1.35 (standard support). AMI `AL2023_ARM_64_STANDARD`. Auth mode `API` (no aws-auth ConfigMap).
- **Namespaces:** `petclinic-dev`, `petclinic-prod`
- **Labels:** Every resource: `app.kubernetes.io/name`, `app.kubernetes.io/part-of=petclinic`, `app.kubernetes.io/managed-by=Helm`
- **Probes:** Every Deployment MUST have startupProbe, readinessProbe, and livenessProbe using `/actuator/health/{readiness,liveness}` (config-server uses `/actuator/health` for all three)
- **Resources:** Every container MUST have requests and limits (memory: 128Mi request / 512Mi limit)
- **Image tags:** Use commit SHA tags, never `latest`
- **Secrets:** Use ExternalSecret CRs (`external-secrets.io/v1`) pointing to AWS Secrets Manager — never store secrets in YAML
- **Service startup order:** Config Server → Discovery Server → all others (use init containers)
- **Packaging:** Helm chart (`helm/petclinic-service/`), per-service + per-env values in `helm-values/`
- **Deployment:** ArgoCD GitOps — CI commits image tags to Git, ArgoCD syncs to cluster
- **Pod security:** `runAsNonRoot`, drop ALL capabilities, `seccompProfile: RuntimeDefault`

## Helm Conventions

- **Single generic chart** in `helm/petclinic-service/` shared by all 8 services
- **Per-service config** in `helm-values/{service}.yaml` (ports, env vars, init containers)
- **Per-env config** in `helm-values/{dev,prod}.yaml` (replicas, HPA, PDB, resource quotas, ECR registry)
- **ArgoCD merges values:** service file + env file when deploying
- **Template outputs** validated with `helm template` before commit
- **Never hardcode an AWS account ID** in values or templates — use `{account}.dkr.ecr.eu-central-1.amazonaws.com`

## ArgoCD Conventions

- **CI pushes images**, ArgoCD deploys. GitHub Actions NEVER runs `kubectl apply`.
- **Dev:** auto-sync enabled (prune + self-heal)
- **Prod:** manual sync required (approval via ArgoCD UI/CLI — not GitHub Environments)
- **Application CRDs** in `k8s/argocd/applications/{dev,prod}/`
- **One Application per service per environment** (16 total: 8 services × 2 envs)

## Security Rules (NON-NEGOTIABLE)

1. **No secrets in code** — use AWS Secrets Manager + External Secrets Operator
2. **No public S3 buckets** — block public access on all buckets
3. **No open security groups** — no 0.0.0.0/0 ingress except ALB on 80/443
4. **Encryption everywhere** — RDS encryption at rest (AWS-managed `aws/rds`), S3 SSE-S3 (AES256), EBS encryption, Secrets Manager KMS
5. **Least privilege IAM** — specific actions on specific resources, never `*/*`
6. **Private nodes and RDS** — public subnets only for ALB and the NAT instance (ADR-0001). Security groups stay mandatory. No SSH, no bastion; operator host debug is SSM Session Manager (nodes + NAT). No interface VPCEs.
7. **No terraform destroy without approval** — hooks block this command
8. **No *.tfvars, *.tfvars.json, or .env files committed** — .gitignore enforces this
9. **EKS API is never 0.0.0.0/0** — public endpoint is `my_ip` `/32` passed at apply (`-var="my_ip=$(curl -s https://checkip.amazonaws.com)/32"`). Never commit it. Re-apply workload when the laptop IP changes.
10. **IMDSv2 required, hop limit 1** on node launch templates (blocks pod IMDS credential theft)
11. **RDS is not publicly accessible** and sits in private subnets (no IGW route)
12. **Prod deletion protection** on RDS; prod takes a final snapshot

## AWS Environment Details

| Setting | Dev | Prod |
|---------|-----|------|
| Region | eu-central-1 | eu-central-1 |
| K8s namespace | petclinic-dev | petclinic-prod |
| Kubernetes | 1.35 (EKS standard support) | 1.35 (EKS standard support) |
| Node AMI | AL2023_ARM_64_STANDARD | AL2023_ARM_64_STANDARD |
| State key | `petclinic/dev/network/terraform.tfstate` + `petclinic/dev/workload/terraform.tfstate` | `petclinic/prod/network/terraform.tfstate` + `petclinic/prod/workload/terraform.tfstate` |
| RDS instance | db.t4g.micro, MySQL 8.4, gp3, single-AZ | same size; deletion protection on |
| EKS nodes | 2x t4g.small ARM | 2x t4g.small ARM |
| Deploy mode | ArgoCD auto-sync | ArgoCD manual sync |
| Replicas | 1 per service | 2+ per service, HPA |

EKS versions in **extended** support cost $0.60/hour. Always pin a **standard-support** version (`upgrade_policy.support_type = STANDARD`). See `saas-ntier-lab` for the same pin.

## Application Services (8 total)

| Service | Port | Needs MySQL | Notes |
|---------|------|-------------|-------|
| config-server | 8888 | No | Must start first, Git-backed config |
| discovery-server | 8761 | No | Eureka, must start second |
| api-gateway | 8080 | No | Frontend + routing, public-facing |
| customers-service | 8081 | Yes | Owners & pets |
| visits-service | 8082 | Yes | Visit records |
| vets-service | 8083 | Yes | Vet data, Caffeine cache |
| genai-service | 8084 | Optional | Needs OPENAI_API_KEY |
| admin-server | 9090 | No | Spring Boot Admin dashboard |

## Docker Image Details

- Base: `eclipse-temurin:17`, memory limit 512M
- **Target platform:** `linux/arm64` (required for Graviton t4g nodes)
- Profile: `SPRING_PROFILES_ACTIVE=docker` (set in container)
- MySQL profile: add `mysql` to active profiles for RDS-backed services
- ECR repos: `{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/{service-name}`
- CI/CD builds require `docker buildx` + QEMU for ARM cross-compilation on x86 runners

## Workflow Commands

```bash
# Terraform workflow (always plan before apply)
terraform fmt -recursive
terraform validate
terraform plan -out plan.out
terraform apply plan.out        # Never apply without a saved plan

# Helm template validation
helm template my-release helm/petclinic-service/ -f helm-values/{service}.yaml -f helm-values/{env}.yaml

# ArgoCD (after install)
kubectl port-forward svc/argocd-server -n argocd 8443:443
argocd app sync {service}-{env}

# Security scanning
checkov -d terraform/modules/{module}
```

## MCP Servers (configured in .cursor/mcp.json)

Work is tracked in `docs/jira-backlog.md` (local). There is no Jira MCP.

| Server | Why we have it |
|--------|----------------|
| `terraform` | HashiCorp Terraform MCP (`hashicorp/terraform-mcp-server`). Live Registry docs for AWS provider ~> 6.0 resources/modules. AWS Labs yanked their package. Does not run Checkov or `terraform apply`; Checkov is CLI (`security-scan`). Destroy via MCP is still blocked by the hook. |
| `aws-knowledge-mcp` | Official AWS docs and regional availability (EKS 1.35 add-ons, RDS MySQL 8.4 in eu-central-1). |
| `awslabs.aws-pricing-mcp-server` | Cost estimates for EKS/EC2/RDS/ALB in eu-central-1. Uses profile `petclinic`. |
| `context7` | Current Terraform / Kubernetes / Helm library docs (not training-data guesses). |

Enable these in Cursor Settings → MCP after cloning. They are inactive until trusted. Requires `bash` + `curl` (Terraform MCP binary), `uvx` (pricing), and `npx` (Context7).

## CI/CD Pipeline Conventions

- **Architecture:** CI (GitHub Actions) + CD (ArgoCD). GitHub Actions NEVER deploys directly.
- **CI Platform:** GitHub Actions, OIDC federation to AWS (no long-lived credentials)
- **Image tags:** Commit SHA (`${GITHUB_SHA::7}`), never `latest`
- **ECR login:** `aws ecr get-login-password --region eu-central-1`
- **Image tag update:** CI commits new tag to `helm-values/{service}.yaml` → ArgoCD picks up
- **Prod gates:** ArgoCD manual sync (not GitHub Environments)
- **Scanning:** Trivy scan after Docker build, fail on CRITICAL CVEs
- **Actions:** pin third-party actions to a commit SHA, not `@vN` or `@latest`

## Safety Hooks (configured in .cursor/hooks.json)

| Hook | Type | What it catches |
|------|------|-----------------|
| `block-destroy.sh` | Block | `terraform destroy`, `terraform apply -destroy`, `kubectl delete` ns/deploy/svc/ingress/secret in prod |
| `block-dangerous-rm.sh` | Block | `rm -rf` on terraform/, k8s/, helm/, helm-values/, .github/, .cursor/, docs/, scripts/ |
| `warn-apply-without-plan.sh` | Ask | `terraform apply` without a saved plan.out file |
| `suggest-validate.sh` | Info | Suggests validate/dry-run after editing .tf, K8s .yaml, Helm, or pipeline files |
| `block-secret-commit.sh` | Block | `git add .`, committing .env, .tfvars, .tfvars.json, .pem, .key files |
| `block-mcp-destroy.sh` | Block | `destroy` via MCP Terraform/Terragrunt tools |

## Technical Specification

All infrastructure values (CIDRs, ports, instance sizes, security groups, K8s resources, probe timings, alert thresholds, version pins) are in [`docs/technical-spec.md`](docs/technical-spec.md). Every Jira story references the relevant spec section. **Read the spec before implementing any story.**

## Jira Backlog

Work is tracked in `docs/jira-backlog.md`. Dependency chain: E-0 → E-1 → VPC → EKS → K8s → Helm → ArgoCD; VPC → RDS → Secrets → K8s.
