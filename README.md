# Petclinic Platform — AWS Infrastructure

Training repo for deploying [Spring Petclinic Microservices](https://github.com/spring-petclinic/spring-petclinic-microservices) (8 Spring Boot / Spring Cloud services) to AWS.

The application repository is **read-only**. All infrastructure lives here and is implemented story-by-story from [`docs/jira-backlog.md`](docs/jira-backlog.md). Values and version pins are in [`docs/technical-spec.md`](docs/technical-spec.md). Agent instructions are in [`AGENTS.md`](AGENTS.md).

## What exists now vs what you will build

**In the repo today:** `AGENTS.md`, `.cursor/` (rules, agents, skills, hooks, MCP), `docs/`, cost-control scripts, `.gitignore`.

**Story outputs (not present until the matching epic):** `terraform/`, `helm/`, `helm-values/`, `k8s/`, `.github/workflows/`, runbooks, ADRs.

```
petclinic-platform/
├── AGENTS.md                     # Cursor project instructions
├── .cursor/                      # Rules, subagents, skills, hooks, MCP
├── terraform/                    # E-1+  environments/{dev,prod} + modules
├── helm/petclinic-service/       # E-16  generic chart for all 8 services
├── helm-values/                  # E-16  per-service + per-env values
├── k8s/                          # E-8 / E-17  namespaces, ESO, ArgoCD
├── .github/workflows/            # E-10  CI only (ArgoCD is CD)
├── scripts/                      # start-env / stop-env / env-status
└── docs/                         # technical-spec, jira-backlog, later runbooks
```

Do not commit `terraform.tfvars`, `*.tfvars.json`, `backend.hcl`, `.env`, or kubeconfig. Use `*.tfvars.example` / `backend.hcl.example` placeholders. Never put `my_ip` or an AWS account ID in Git.

## Operator IP (EKS API)

The laptop public IP changes every connection. Same as saas-ntier-lab: pass it on the CLI when you plan/apply the **learning** stack.

```bash
-var="my_ip=$(curl -s https://checkip.amazonaws.com)/32"
```

That CIDR is the EKS public API allow-list. Re-apply after you reconnect. Never `0.0.0.0/0`.

## Tech Stack

| Layer | Tool | Details |
|-------|------|---------|
| Cloud | AWS | eu-central-1 |
| IaC | Terraform >= 1.6 | AWS provider ~> 6.0, S3 + DynamoDB state, **SSE-S3 (AES256)** — deliberate (ADR-0012), not a customer CMK |
| Cluster | Amazon EKS 1.35 | Standard support, AL2023 ARM nodes, API auth, CIDR-restricted public API |
| Registry | Amazon ECR | One repo per service per env, lifecycle, scan-on-push |
| Database | Amazon RDS MySQL 8.4 | db.t4g.micro, gp3, single-AZ, not publicly accessible |
| DNS | Route 53 + ACM | TLS termination at ALB |
| Secrets | AWS Secrets Manager | External Secrets Operator (`external-secrets.io/v1`) |
| Ingress | AWS Load Balancer Controller | `ingressClassName: alb` → API Gateway |
| Observability | Prometheus + Grafana + Loki | In-cluster metrics and logs |
| Tracing | Zipkin | OpenTelemetry |
| CI | GitHub Actions | OIDC → AWS, build → push ECR → commit image tag |
| CD | ArgoCD | Dev auto-sync, prod manual sync |
| Packaging | Helm | Generic chart, per-service + per-env values |
| Node scaling | Karpenter | NodePool + EC2NodeClass (v1 APIs) |

## Environments

| Environment | K8s Namespace | Kubernetes | RDS | Deploy |
|-------------|---------------|------------|-----|--------|
| dev | `petclinic-dev` | 1.35 | db.t4g.micro, skip final snapshot | ArgoCD auto-sync |
| prod | `petclinic-prod` | 1.35 | db.t4g.micro, deletion protection | ArgoCD manual sync |

EKS extended support is $0.60/hour. Always pin a **standard-support** version.

## Cost habit

EKS control plane is $0.10/hour (~$73/month) **while the cluster exists** — there is no stop. Destroy the learning stack after each session (keep the VPC). Target: **entire course under $20**, which holds at ~10 hours/week if you never leave EKS overnight. One forgotten weekend is ~$5 of that $20.

## Cursor setup

1. Prefer **File → Open Workspace from File…** → `petclinic.code-workspace` (adds AI-DLC + lab clones as read-only knowledge). Or open this folder alone.
2. Trust the workspace. Enable project MCP from `.cursor/mcp.json` (Settings → MCP).
3. Confirm hooks under Settings → Hooks.
4. Read [`docs/ai-sdlc.md`](docs/ai-sdlc.md) for architect → implementer → reviewer. Spec/backlog remain the course crossword unless you accept an ADR.
