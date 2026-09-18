---
name: review-terraform
description: Reviews Terraform against petclinic naming, tags, encryption, EKS 1.35, and least-privilege IAM. Use when reviewing .tf files or after generating a module.
---

# review-terraform

Read-only review. Does not modify files.

## Arguments

- `path` — module directory, environment, or file (default: `terraform/`)

## Steps

1. Read the target `.tf` files
2. Check against AGENTS.md and terraform rules:
   - Naming `petclinic-{env}-{resource}`
   - Module files: main/variables/outputs/versions
   - AWS provider ~> 6.0
   - No hardcoded secrets
   - Encryption, SG posture, EKS API CIDR, IMDSv2 hop 1
   - Tags Project / Environment / ManagedBy
   - K8s 1.35, AL2023_ARM_64_STANDARD, auth mode API
3. Report:

```
## Terraform Review: {path}

### Issues Found
- [SECURITY] {description} — {file}:{line}

### Good Practices Observed
### Summary
Files reviewed: N | Issues: N (critical: N, warning: N, info: N)
```

Prioritize security over naming. Reference file:line.
