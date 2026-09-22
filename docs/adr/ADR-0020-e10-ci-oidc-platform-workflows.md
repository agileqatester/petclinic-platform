# ADR-0020: E-10 CI — OIDC in the keep network; platform updates tags; the fork builds

**Status:** Accepted
**Date:** 2026-09-22
**Context:** Epic E-10 (`PETPLAT-49`, `50`, `52`; `PETPLAT-51` already removed) is CI only. ArgoCD (E-17) deploys. There is no `.github/` tree yet. The Spring application repo is read-only, so `build-push.yml` cannot be committed there. ECR `petclinic-dev/{service}` already exists in the keep network stack. The workload is not applied. `helm-values/{service}.yaml` does not exist yet (ADR-0019, E-16). Do not apply in this epic. Never commit an AWS account ID. Prod deploy stays ArgoCD manual sync.

GitHub OIDC (`token.actions.githubusercontent.com`) is account-level IAM, not the EKS IRSA issuer. It must survive workload destroy so CI can push images while the cluster is down, same as ECR (ADR-0014).

**Decision:** Author CI plumbing in this platform repo, plus a reference workflow to copy into an application fork later. Do not modify the read-only application repo. Do not apply Terraform. Do not require a live pipeline run.

### What is written where

| Piece | Where | When |
|-------|--------|------|
| OIDC provider + role `petclinic-github-actions-role` | `terraform/environments/dev/network` (keep, next to ECR) | Author now. Apply is a later gate. |
| `.github/workflows/update-image-tags.yml` | This repo | Author now |
| Reference `build-push.yml` | This repo, not an active app workflow (for example `.github/workflow-templates/`) | Author now, for the operator to copy |
| Live `build-push.yml` | The operator’s application fork | Copy later. Not this repo’s upstream app tree. |
| GitHub secrets `AWS_REGION`, `AWS_ROLE_ARN`, `AWS_ACCOUNT_ID`, `PLATFORM_REPO_TOKEN` | Fork settings | After the OIDC apply. Account ID only as a secret. |

`update-image-tags.yml` does not assume the AWS role. It checks out this repo, sets `image.tag` with `yq`, and pushes. ECR login belongs to the fork build.

### OIDC role (PETPLAT-52)

- Provider `token.actions.githubusercontent.com`, audience `sts.amazonaws.com`.
- Trust subject `repo:{org}/{app-fork}:ref:refs/heads/main`. Exact fork and `main` only. `{org}/{repo}` comes from gitignored tfvars. No wildcard repo or ref.
- Role name `petclinic-github-actions-role`.
- ECR push only on the eight `petclinic-dev/{service}` repository ARNs (PutImage, layer upload, BatchCheck, plus `BatchGetImage` and `GetDownloadUrlForLayer` so `docker push` can reuse layers already in the repo). `ecr:GetAuthorizationToken` stays `Resource: "*"` because AWS requires it. No other action uses `*`.
- No Terraform state, S3, DynamoDB, EKS, or Secrets Manager permissions.

### Workflows

- **Build (fork):** `linux/arm64`, Buildx + QEMU, Trivy fails on CRITICAL, tag `${GITHUB_SHA::7}`, push to `{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-dev/{service}:{sha}`, then `repository_dispatch` type `app-image-built` with the SHA and the changed services. Path filter so unchanged services are not built. Third-party actions pinned to a commit SHA.
- **Tags (platform):** `repository_dispatch` type `app-image-built`. Commit message `ci: update image tags to {sha} ({service-list})`. No `kubectl`. No `aws eks update-kubeconfig`.

Until E-16 creates `helm-values/{service}.yaml`, a real dispatch fails on missing files. That is expected. ArgoCD verification waits on E-16, E-17, and a cluster.

### Deferred

| Story | Disposition |
|-------|-------------|
| PETPLAT-53 | Defer. The build and the tag update live in different repos. |
| PETPLAT-54 | Defer. Rollback needs ArgoCD and a deployed revision (E-15 / after E-17). |

**Consequences:**
- Positive: CI can push while the cluster is down. Trust is one fork on `main`. ECR write is `petclinic-dev/*`. Account ID stays out of git. OIDC and the role are $0. No EKS bill to push an image.
- Negative: The operator copies `build-push.yml` and sets fork secrets. The tag workflow is inert until E-16. The next network apply, when chosen, creates the OIDC provider and role.
- Cost: OIDC and IAM $0. ECR storage remains about $1/month after images exist. GitHub Actions minutes for QEMU ARM builds. No NAT or EKS charge for push-only CI.
- Security: No long-lived keys. No cluster API from CI. Trivy CRITICAL gate on the build path.

**Rejected:**
- Long-lived AWS keys in GitHub (ADR-0005).
- `kubectl` or a deploy workflow from Actions (PETPLAT-51 removed).
- Committing an account ID or a registry host that contains one.
- Editing the read-only application repo in place.
- A prod deploy workflow or a GitHub Environment approval gate. Prod stays ArgoCD manual sync.
- Putting the CI role in the destroyable workload. Destroy would remove the ability to push.
- Waiting to author `update-image-tags.yml` until E-16. Author now. Live verify waits.
- PETPLAT-53 and a live PETPLAT-54 test as E-10 must-pass.
- Trust on `repo:{org}/*` or any ref.
- `Resource: "*"` on ECR push and layer APIs. Only `GetAuthorizationToken` uses `*`.

**Still applies after accept:** PETPLAT-52 authors the role in dev/network and skips apply. PETPLAT-49 is a reference here and a live workflow in the fork later. PETPLAT-50 is authored now; ArgoCD verify waits. PETPLAT-53 and PETPLAT-54 leave this epic. ADR-0005, ADR-0014, and ADR-0019 are unchanged.
