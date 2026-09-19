---
name: write-adr
description: Writes an Architecture Decision Record in docs/adr using the project template. Use when the architect or user records a platform choice (VPC, NAT, EKS, GitOps) or revises ADR-0001.
disable-model-invocation: true
---

# write-adr

## Location

`docs/adr/ADR-NNNN-short-title.md` (create `docs/adr/` if needed).

## Template

```markdown
# ADR-{number}: {title}

**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-{N}
**Date:** YYYY-MM-DD
**Context:** {problem}
**Decision:** {what and why}
**Consequences:** {positive and negative}
```

## Rules

- No secrets, account IDs, or personal emails.
- Include rejected options (e.g. NAT Gateway vs NAT instance vs all-public).
- Point at spec/backlog IDs only if they still apply after the decision.
- Default status is **Proposed** until the user accepts.
