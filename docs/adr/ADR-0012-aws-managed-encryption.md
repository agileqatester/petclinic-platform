# ADR-0012: AWS-managed encryption for Terraform state and RDS

**Status:** Accepted
**Date:** 2026-09-19
**Context:** The state bucket was created with a customer-managed KMS CMK (`alias/petclinic-terraform-state`, ~$1/month). ADR-0001 said RDS should reuse that same key so a second CMK did not add another $1. The bucket has no useful state yet. Keeping a CMK for a learning account that already accepts AWS-managed keys for EBS, ECR, and Secrets Manager is cost without extra control we will use.

**Decision:** Encrypt the Terraform state bucket with SSE-S3 (AES256). Do not set `kms_key_id` on the S3 backend. When RDS is implemented, omit `kms_key_id` so storage uses the AWS-managed `aws/rds` key. Do not create a petclinic CMK. Schedule deletion of the leftover `alias/petclinic-terraform-state` key.

**Consequences:**
- Positive: Drops the ~$1/month CMK. No KMS key policy or RDS `CreateGrant` work. Matches EBS/ECR/Secrets Manager in the encryption matrix. Empty bucket, so no state migration.
- Negative: No customer-managed key policy, CloudTrail key events, or independent rotation schedule. Fine for this learning account; not the posture for a regulated production account.
- Rejected — keep one CMK for S3 + RDS: cheapest *if* the key must stay because the bucket already has KMS objects. That is not the case here.
- Rejected — second RDS CMK: another $1/month for no extra control.
- Rejected — SSE-KMS with `alias/aws/s3`: also $0/month for the key, but still KMS API calls and a `kms_key_id` on the backend. SSE-S3 is simpler.

**Still applies after accept:** PETPLAT-2/3/4 (bootstrap + backends use AES256, no `kms_key_id`), PETPLAT-22 (RDS `storage_encrypted = true`, no custom `kms_key_id`). Supersedes the CMK sentence in ADR-0001.
