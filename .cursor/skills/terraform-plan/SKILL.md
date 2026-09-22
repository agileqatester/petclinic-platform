---
name: terraform-plan
description: Runs terraform init and plan for the dev or prod environment and summarizes adds/changes/destroys. Use when the user asks to plan infrastructure, run terraform plan, or preview AWS changes.
disable-model-invocation: true
---

# terraform-plan

Run Terraform init and plan for the specified environment.

## Arguments

- `env` — `dev` or `prod` (default: `dev`)

## Steps

1. Default `env` is `dev`. Do not plan prod for day-to-day learning.
2. Ensure `terraform/backend.hcl` exists (`./scripts/write-backend-config.sh`) and each root has gitignored `terraform.tfvars` with `aws_account_id` (copy from `*.tfvars.example`).
3. Plan **network** first: `terraform/environments/{env}/network/`
   - `terraform init -backend-config=<repo>/terraform/backend.hcl`
   - `terraform plan -var-file=terraform.tfvars -out plan.out`
   - `-var="my_ip=..."` is optional here (declared, unused). Same CLI as workload is fine.
4. Workload (`.../{env}/workload/`) only after network state exists in S3. Same init; plan **must** pass the operator IP (never tfvars):
   - `terraform plan -var-file=terraform.tfvars -var="my_ip=$(curl -s https://checkip.amazonaws.com)/32" -out plan.out`
5. Summarize adds / changes / destroys. Warn explicitly if anything will be destroyed.

## Important

- Always use `-out plan.out`
- Never apply from this skill
- If init fails, show the error (missing backend, provider constraints)
