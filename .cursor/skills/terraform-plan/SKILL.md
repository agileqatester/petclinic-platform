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

1. Directory: `terraform/environments/{env}/`
2. `terraform init`
3. `terraform plan -out plan.out`
4. Summarize adds / changes / destroys. Warn explicitly if anything will be destroyed.

## Important

- Always use `-out plan.out`
- Never apply from this skill
- If init fails, show the error (missing backend, provider constraints)
