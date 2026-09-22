# ADR-0017: Non-RDS secrets and ESO IRSA in the destroyable workload

**Status:** Accepted
**Date:** 2026-09-22
**Context:** Epic E-7, **dev only**. Network is applied (VPC + 8 ECR). Skip workload apply (no NAT/EKS/RDS live). Skip prod. Skip DNS (ADR-0016). Config-server uses a **public** GitHub config repo. App repo stays read-only. Never commit an AWS account ID or secret values.

ADR-0011 already accepted **Secrets Manager** over SSM/K8s Secrets. ADR-0012 already accepted **AWS-managed keys** (no petclinic CMK; SM uses `aws/secretsmanager`). ADR-0015 already placed **RDS + `petclinic/{env}/rds-credentials`** in workload; `terraform/modules/secrets/` is **non-RDS only**. This file does not reopen those. The missing decisions are: **which Terraform root** calls the secrets module, **how the OpenAI value is supplied**, **where ESO IRSA lives**, and **what YAML can be written without a cluster**.

Two existing roots. **Network** = keep (already applied). **Workload** = destroy (NAT + EKS + RDS + LBC IRSA authored, not applied). Secrets Manager is **$0.40/secret/month** in eu-central-1, billed while the secret exists, independent of EKS. A keep-stack OpenAI secret would start that bill on the next **network** apply, with no cluster to consume it. IAM IRSA is $0, but the trust policy needs the cluster OIDC issuer — same constraint as LBC (`terraform/environments/dev/workload/lbc.tf`). saas-ntier-lab puts tenant SM secrets and IRSA in **workload** with `recovery_window_in_days = 0`. ESO talks to the SM public API over the NAT instance (ADR-0001: no Secrets Manager interface VPCE).

GenAI defaults `OPENAI_API_KEY` to `demo` if unset. A real key is optional for the course. PETPLAT-33’s optional `config-server/git-username` / `git-password` are not needed for a public config repo.

**Decision:** Call `terraform/modules/secrets/` from **`terraform/environments/dev/workload` only**. Do not call it from network. Do not add a third root. Do not wire prod. `recovery_window_in_days = 0`. Omit `kms_key_id` (default `aws/secretsmanager`). Secret name `petclinic/dev/openai-api-key`, **plaintext** (not JSON), matching the ExternalSecret `OPENAI_API_KEY` mapping. RDS credentials stay in the RDS module.

**OpenAI value:** sensitive variable `openai_api_key`, **default `""`**. Create the secret **only when the value is non-empty** (`count` / gated module, same idea as ADR-0016 `domain_name`). Pass at apply via `-var` or `TF_VAR_openai_api_key`. Do **not** put it in committed tfvars (`.example` may comment the flag only — no `sk-` placeholder). Do **not** create an empty or `demo` secret. Do **not** AWS-generate a string. Skip both git credential secrets.

**ESO IRSA:** author in **workload**, same pattern as `lbc.tf` (not inside `modules/secrets/`, which has no OIDC). Role `petclinic-dev-eso-role`. Trust `sts:AssumeRoleWithWebIdentity` on `module.eks` OIDC, scoped to `system:serviceaccount:external-secrets:external-secrets-sa` and `aud=sts.amazonaws.com`. Policy: `secretsmanager:GetSecretValue` + `secretsmanager:DescribeSecret` on `arn:aws:secretsmanager:eu-central-1:{account}:secret:petclinic/*` (`data.aws_caller_identity`, never a committed account ID). **No `kms:Decrypt`** — PETPLAT-37’s CMK line does not apply under ADR-0012. Output `eso_role_arn` for the SA annotation at install time (same as `lbc_role_arn`).

**YAML vs install:**

| Piece | Keep vs destroy | When |
|--------|-----------------|------|
| `terraform/modules/secrets/` (OpenAI SM secret) | **Destroy**, workload | **Code now.** Gated on non-empty `openai_api_key`. **Skip apply.** |
| ESO IRSA (`eso.tf` next to `lbc.tf`) | IAM $0; OIDC dies with cluster → **workload** | **Code now. Apply waits on E-3** (same as LBC). |
| ESO install (PETPLAT-34: kubectl apply, CRDs + controller) in `external-secrets` | Destroy with cluster | **Wait** on E-3 apply. Annotate SA with `eso_role_arn` at install. Do not add `helm_release`. |
| `ClusterSecretStore` `aws-secrets-manager` (`external-secrets.io/v1`, region `eu-central-1`, JWT SA `external-secrets-sa`) | Git only until apply | **Write now. Do not apply** (no CRDs). |
| ExternalSecret RDS (`k8s/base/external-secrets/rds-credentials.yaml`) | Git | **Write now:** namespace `petclinic-dev` (created in E-8, same as Ingress), `refreshInterval: 1h`, JSON `username`/`password` from `petclinic/dev/rds-credentials`. **Do not apply.** |
| ExternalSecret OpenAI (`k8s/base/external-secrets/openai-api-key.yaml`) | Git | **Write now.** Apply later only if the SM secret exists (non-empty key). **Do not apply this epic.** |

Skip PETPLAT-34/35/36 **install and `kubectl get secret` verify** until E-3 is applied. First future workload apply still does not install ESO unless that install is explicitly opened (same as LBC Helm).

**Consequences:**
- Positive: OpenAI does not add $0.40/month to the already-applied keep stack. With an empty key, SM cost for this module is **$0**. With a key, the secret dies with workload destroy (`recovery_window 0`), same habit as RDS credentials. IRSA cannot dangle after cluster destroy. YAML and HCL can be reviewed without EKS. Public config repo needs no extra SM objects. Least-privilege `petclinic/*`, no CMK, no secret values in Git.
- Negative: Re-supply the OpenAI key on the next workload apply (same class of `-var` as `my_ip`). Gated secret means the OpenAI ExternalSecret will not sync until a key is passed. Workload apply remains coupled (NAT + EKS + RDS + LBC IAM + ESO IAM + optional OpenAI). `sensitive = true` redacts CLI; state still holds the value under SSE-S3.
- Rejected — **network (keep)** for OpenAI: $0.40/month always-on after apply; network is already live so the bill starts without a consumer; contradicts destroy-after-session; IRSA still could not live there.
- Rejected — **third root** (`environments/dev/secrets`): extra state key; spec documents two; two destroys after a session.
- Rejected — **always create** the secret with empty/`demo` string: still $0.40/month; teaches a fake credential path; GenAI already defaults to `demo` in-process.
- Rejected — **required** `openai_api_key` with no default: blocks `terraform plan` for people without a key.
- Rejected — **AWS-generated** password as the API key: not a valid OpenAI credential.
- Rejected — **git-username/password** secrets: unused for public GitHub config.
- Rejected — **RDS credentials in `modules/secrets/`:** ADR-0015 / PETPLAT-23.
- Rejected — **ESO IRSA in network or inside `modules/secrets/`:** OIDC URL comes from the cluster; LBC pattern is workload-root HCL. Keep-stack IAM would dangle after destroy.
- Rejected — **`kms:Decrypt`:** only needed for a customer CMK (ADR-0012).
- Rejected — **SM interface VPCE:** ADR-0001; ESO uses NAT during a session.
- Rejected — **Terraform `helm_release` / apply CRs this epic:** no cluster; PETPLAT-34 stays kubectl **after** E-3, like LBC Helm.
- Rejected — **prod** this epic.

**Still applies after accept:** PETPLAT-33 (**module + wire `dev/workload`**, gated OpenAI, skip git secrets, `terraform validate`; **skip apply**). PETPLAT-37 (**author IRSA** in workload like LBC; **skip apply**). PETPLAT-34: **author** ClusterSecretStore (+ SA name/annotation notes); **install/verify blocked** on E-3 apply. PETPLAT-35/36: **write** ExternalSecret YAML; **skip apply and `kubectl get secret`**. **Skip** prod. PETPLAT-85 (rotation) stays later. ADR-0011 / 0012 / 0015 / 0016 unchanged.
