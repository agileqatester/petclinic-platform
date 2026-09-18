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

Do not commit `terraform.tfvars`, `.env`, or kubeconfig. Use `*.tfvars.example` placeholders.

## Tech Stack

| Layer | Tool | Details |
|-------|------|---------|
| Cloud | AWS | eu-central-1 |
| IaC | Terraform >= 1.6 | AWS provider ~> 6.0, S3 + DynamoDB state, SSE-KMS |
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

EKS control plane is ~$73/month per cluster while it exists. Use `scripts/stop-env.sh {dev|prod}` between sessions, or destroy the environment. Target: entire course under $50 AWS spend.

## Cursor setup

1. Open this folder in Cursor and trust the workspace.
2. Enable project MCP servers from `.cursor/mcp.json` (Settings → MCP).
3. Confirm hooks appear under Settings → Hooks.
4. Implement stories in epic order: E-0 is done in-tree; start E-1 (remote state) next.
