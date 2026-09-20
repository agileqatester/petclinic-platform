# ADR-0014: ECR private repositories in the keep-stack network root

**Status:** Accepted
**Date:** 2026-09-20
**Context:** Epic E-4, **dev only**. Skip E-3 apply (EKS/NAT not live). Skip prod wire/deploy. Intent: eu-central-1, profile petclinic, eight Spring services, course ~$20 with destroy discipline. Application repo is read-only. Never commit an AWS account ID.

ADR-0010 (index-only) already accepted **private** ECR: IAM access, lifecycle, scan-on-push, tag immutability, ~$1/month. This file does not reopen public vs private. The missing decision is **which Terraform root calls** `terraform/modules/ecr/`.

Two existing roots (ADR-0001 / ADR-0013): **network** = keep (VPC, S3 gateway, baseline SGs; idle ~$0); **workload** = destroy (NAT + EKS; later RDS/ALB). EKS in workload would bill $0.10/h if left in keep. ECR is a **regional** control-plane service (not VPC-attached). Storage is $0.10/GB-month in eu-central-1 after a 500 MB free tier. Eight services × ~200 MB, lifecycle keep last 10 → about 8–10 GB → **~$1/month**, always-on, independent of NAT/EKS.

E-4 is blocked by E-1 only (not E-3). CI (E-10) must push while the cluster is down. Workload is already wired with NAT + EKS (not applied). A workload apply would create those too. `-target` is not an apply strategy. S3 gateway is already on private route tables: it carries ECR **layers**; ECR **API** still needs NAT when nodes exist. That datapath is unchanged.

**Decision:** Place the eight private ECR repositories in the **keep** stack. Call `terraform/modules/ecr/` from `terraform/environments/dev/network` only this epic. Do not call it from workload. Do not add a third root. Do not call it from `environments/prod/network` this epic.

Repos: `petclinic-dev/{service}` via `aws_ecr_repository` for config-server, discovery-server, api-gateway, customers-service, visits-service, vets-service, genai-service, admin-server. Scan-on-push on. Encryption AES256 (ECR default; no customer CMK — ADR-0012). Tag mutability **MUTABLE** in dev (prod **IMMUTABLE** when that root is wired later). Lifecycle: keep last 10 images; also expire untagged after 7 days (PETPLAT-18/19). Image tags are commit SHA (7 chars); never `latest`. Registry URL is an output, not a committed account ID.

PETPLAT-20 **wire** is this epic’s implementation. PETPLAT-20 **apply** is a later human gate (plan skill, then explicit apply). Do not apply as part of architecture or code.

**Consequences:**
- Positive: Images and scan findings survive `terraform destroy` of workload. Network apply can create repos without NAT/EKS. CI can push with the cluster down. Always-on cost is cents to ~$1/month — keep-stack economics, not $0.10/h. Matches E-4’s independence from E-3. Private + scan-on-push + AES256 + no public policy.
- Negative: Network state is no longer “VPC only.” Destroying the VPC (not the habit) would also delete repos. Empty repos still exist until someone deletes them; lifecycle only helps after images exist.
- Rejected — (B) `environments/dev/workload`: destroy-after-session wipes images (and needs `force_delete`). Same apply as unapplied NAT/EKS, which contradicts skip E-3 apply. Couples E-4 to E-3 though the backlog does not.
- Rejected — (C) third root (`environments/dev/ecr` or `registry/`): extra state key (`petclinic/dev/ecr/terraform.tfstate`), backend, and apply for a ~$1/month regional resource. Spec documents two keys. Purity without a cost or safety gain.
- Rejected — (D) public ECR: ADR-0010. Public pull, no IAM gate on get, teaches the wrong pattern. Storage is still ~$0.10/GB-month — no meaningful saving.
- Rejected — Inspector enhanced scanning / customer CMK for ECR: extra SKUs; spec is basic scan-on-push + AES256.
- Rejected — interface ECR VPCEs so nodes skip NAT: ADR-0001; ~$9/month per endpoint-AZ.

**Still applies after accept:** PETPLAT-18 (module `aws_ecr_repository`, scan-on-push, `petclinic-{env}/`, outputs), PETPLAT-19 (lifecycle + mutability), PETPLAT-20 (**wire** from **dev/network**; **apply later**), PETPLAT-21 (`scripts/ecr-login.sh` after apply). ADR-0010 unchanged (private). ADR-0001 / ADR-0012 / ADR-0013 unchanged. No prod ECR story this epic.
