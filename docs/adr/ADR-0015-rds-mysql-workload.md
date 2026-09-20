# ADR-0015: RDS MySQL and credentials in the destroyable workload

**Status:** Accepted
**Date:** 2026-09-20
**Context:** Epic E-5, **dev only**. Skip E-3 apply (NAT/EKS not live). Skip E-4 apply. Skip prod. Intent: eu-central-1, profile `petclinic`, eight Spring services, course ~$20 with destroy-after-session. App repo is read-only. Never commit an AWS account ID.

ADR-0003 already accepted **one shared `petclinic` database** for customers/visits/vets (cross-service FK `visits.pet_id` → `pets.id`). ADR-0006 already accepted **single-AZ** for both envs. ADR-0012 already accepted **omit `kms_key_id`** (`aws/rds`). This file does not reopen those. The missing decision is **which Terraform root** creates the instance **and** the PETPLAT-23 secret `petclinic/{env}/rds-credentials`.

Two existing roots: **network** = keep (VPC, S3 gateway, baseline SGs including `rds`, ECR). **workload** = destroy (NAT + EKS wired, not applied). Spec already lists RDS on the destroy list. saas-ntier-lab calls `module "rds"` from `env/dev/workload` (same remote-state pattern). RDS is VPC-attached (subnet group + SG on private subnets). It does **not** need NAT or a live cluster to *create*. It **does** need EKS to *verify* from a pod (PETPLAT-26). Credentials belong with the instance: PETPLAT-23 is in E-5, not E-7 (`terraform/modules/secrets/` is OpenAI and other non-RDS secrets only).

eu-central-1 OnDemand: `db.t4g.micro` MySQL Single-AZ **$0.019/hour** (~$14/month if left 24/7). Free tier (750 hrs/12 months, 20 GB) can make a session ~$0 for the instance, but 24/7 still burns the allowance. Secrets Manager **$0.40/secret/month** in Frankfurt. Automated backups/gp3 are extra if the instance stays up. A keep-stack RDS would fight the ~$20 course cap.

**Decision:** Place the MySQL instance, DB subnet group, `random_password`, and Secrets Manager secret **in the destroy stack**. Call `terraform/modules/rds/` from `terraform/environments/dev/workload` only this epic. Do not call it from network. Do not add a third root. Do not call `environments/prod/workload` (skip PETPLAT-27).

Instance: `petclinic-dev-mysql`, engine MySQL **8.4**, `db.t4g.micro`, gp3 20 GB, `max_allocated_storage = 20` (spec table; no real storage autoscaling), `multi_az = false`, `publicly_accessible = false`, private subnet IDs from network remote state (two AZs required for a subnet group even when single-AZ). Attach the **existing** VPC RDS SG (`rds_sg_id`); do not create a second RDS SG. Ingress 3306 is already node-SG-only. `storage_encrypted = true`, omit `kms_key_id`. Dev: `skip_final_snapshot = true`, `deletion_protection = false`, backup retention **7 days**. Master username `petclinic`. Password: `random_password` (16+, special chars MySQL-safe; exclude `/ @ " '` and similar). Secret name `petclinic/dev/rds-credentials`, JSON `{"username":"...","password":"..."}` as the spec’s ESO mapping. `recovery_window_in_days = 0` so destroy does not leave a 30-day replica. Default AWS `aws/secretsmanager` key. Mark password/secret outputs `sensitive = true` (redacts CLI; state still holds the value under SSE-S3).

`db_name = "petclinic"` on the instance so the shared database exists before Spring runs `CREATE DATABASE IF NOT EXISTS`. Schema init remains **Spring auto-init** (`spring.sql.init.mode=always`, `mysql` profile): customers → vets → visits. Document that in PETPLAT-24. Do not copy SQL out of the app repo.

RDS has **no Terraform `depends_on` NAT**. It can create in parallel with EKS. PETPLAT-25 **wires** the module so `terraform plan` in workload shows RDS + secret. PETPLAT-26 **apply is skipped this epic**. First future workload apply will create NAT + EKS + RDS together. That is the learning-stack apply, not `-target`. E-7 (ESO, IRSA, ExternalSecret CRs) still consumes `secret_arn` later.

**Consequences:**
- Positive: RDS hourly cost dies with workload destroy, same habit as NAT/EKS and saas-ntier-lab. Credentials are not orphaned in keep-stack SM at $0.40/month. Private, encrypted, no public RDS, no customer CMK. PETPLAT-23 stays in E-5. Plan/validate can run without a live cluster.
- Negative: Workload apply is now coupled (NAT + EKS + RDS). Skip-E-3-apply still means **do not apply** this epic; when you do apply later, the DB comes up too. `sensitive = true` does not remove the password from state. Single-AZ remains a SPOF (ADR-0006). 7-day backups during a short session are mostly unused.
- Rejected — (B) `environments/dev/network`: can apply RDS without EKS, but 24/7 `db.t4g.micro` is ~$14/month (or burns free-tier hours). Contradicts ADR-0001 destroy list. Secret would survive destroy of the database.
- Rejected — (C) third root (`environments/dev/data`): extra state key; spec documents two. Two destroys after a session. No safety gain vs workload.
- Rejected — `enable_rds` default false (saas): their RDS is optional. Petclinic always needs the shared DB. PETPLAT-25 wants the module called and plan to show it.
- Rejected — RDS `manage_master_user_password`: AWS-owned secret name/JSON; ESO expects `petclinic/{env}/rds-credentials` with `username`/`password`.
- Rejected — password variables / tfvars: PETPLAT-22 AC is stale; PETPLAT-23 + spec win (`random_password` in the RDS module).
- Rejected — Multi-AZ, customer CMK, publicly accessible, interface SM VPCE: ADR-0006 / 0012 / 0001.
- Rejected — putting RDS credentials in `terraform/modules/secrets/`: duplicates PETPLAT-33’s “do not create RDS creds here.”

**Still applies after accept:** PETPLAT-22 (module: MySQL 8.4, subnet group, use existing RDS SG, utf8mb4 parameter group, outputs endpoint/port/id), PETPLAT-23 (SM JSON secret in **this** module), PETPLAT-24 (**document** Spring auto-init + connection string; skip “tested from services” until apply + app), PETPLAT-25 (**wire** `dev/workload` + plan, no apply). **Skip** PETPLAT-26 apply and PETPLAT-27 prod. ADR-0003 / 0006 / 0011 / 0012 / 0013 unchanged.
