---
name: terraform-apply
description: Applies a saved Terraform plan after confirmation. Use only when the user explicitly asks to apply infrastructure changes to AWS.
disable-model-invocation: true
---

# terraform-apply

Apply a previously saved Terraform plan.

## Arguments

- `env` — `dev` or `prod` (default: `dev`)

## Steps

1. Directory: `terraform/environments/{env}/`
2. Require `plan.out`. If missing, tell the user to run the terraform-plan skill first.
3. `terraform show plan.out`
4. Ask for explicit confirmation. For prod, warn that live services are affected.
5. Only after yes: `terraform apply plan.out`
6. Show created/changed/destroyed resources and key outputs.

## Important

- NEVER apply without a saved plan
- NEVER use `-auto-approve`
- If apply fails, show the error and do not retry automatically
