---
name: security-scan
description: Runs Checkov on Terraform modules and categorizes findings. Use when the user asks for a security scan of IaC or before terraform apply.
disable-model-invocation: true
---

# security-scan

Read-only Checkov scan.

## Arguments

- `module` — module name under `terraform/modules/` or `all` (default: `all`)

## Steps

1. Target `terraform/modules/{module}/` or `terraform/`
2. Run `checkov -d {target} --framework terraform --output json` (HashiCorp Terraform MCP does not expose Checkov)
3. Categorize: Critical (public access, missing encryption, wildcard IAM) / High / Medium / Low
4. Note intentional exceptions (all-public subnets, single-AZ RDS)
5. If Critical findings exist, say: fix before applying to any environment.

For a full audit, use the security-auditor subagent.
