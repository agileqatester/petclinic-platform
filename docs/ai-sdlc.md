# AI-SDLC in this training (read this first)

**Last Updated:** 2026-09-19

**Purpose:** Explain how Cursor agents, sibling repos, and AWS AI-DLC fit together. Nothing here copies those repos into petclinic.

## What we are doing

The course backlog (`docs/jira-backlog.md`) + spec (`docs/technical-spec.md`) are a **frozen crossword**. That is fine for grading. It is not how you start a job.

**You are the gate at every stage**, not only after architecture. Agents stop and wait. Say `accept` / `implement` / `review` / `plan` / `apply` to open the next stage.

| # | Stage | Who | You approve before… |
|---|--------|-----|---------------------|
| 1 | Intent | You | Architect runs |
| 2 | Architecture (ADR) | `architect` | Anyone writes `.tf` |
| 3 | Implementation plan | Implementer | File edits |
| 4 | Implementation | Implementer | Review |
| 5 | Review | `terraform-reviewer` / `security-auditor` / `cost-reviewer` | `terraform plan` |
| 6 | Plan | `terraform-plan` skill | `terraform apply` |
| 7 | Apply | You + hook | Live AWS change |

Same idea as AWS AI-DLC human gates, fewer stages. Rule: `.cursor/rules/human-gates.mdc` (`alwaysApply`).

## Knowledge bases (not copied)

Sibling clones on disk. Open `petclinic.code-workspace` so `@folder` works. `AGENTS.md` only *points* at them.

| Folder (sibling of this repo) | Use as |
|-------------------------------|--------|
| `aidlc-workflows` | AWS **AI-DLC** method: stages, architect persona, ADRs. Start at `docs/guide/00-introduction.md` and `core/agents/aidlc-architect-agent.md`. |
| `saas-ntier-lab` | Public lab: **private nodes + t4g.micro NAT instance**, S3 gateway endpoint, EKS API `/32`. Prefer this over all-public subnets when cost allows. |
| `ntier-app` | Private lab + interview docs. Same family as saas. Read-only. Never commit its files here. |

Do **not** run the AI-DLC installer into this repo yet. That would merge `.cursor/hooks.json` and fight E-0. Using `aidlc-workflows` as `@` knowledge is enough until you want `/aidlc` on an empty project.

## How to try it (one network decision)

New Agent chat:

```
Use the architect subagent.

Constraints: eu-central-1, profile petclinic, 8 Spring services, course budget.
@aidlc-workflows/core/agents/aidlc-architect-agent.md
@saas-ntier-lab/modules/nat
Revise ADR-0001: private EKS nodes + NAT instance vs all-public IGW.
No Terraform. Stop for my approval.
```

Then wait. When you accept the ADR, a **new** chat: implementation **plan** only. After you accept the plan: code. Then review, then plan, then apply — each a separate proceed.

## Cursor pieces in this repo

| Piece | Path | Role |
|-------|------|------|
| Architect | `.cursor/agents/architect.md` | Design only |
| Reviewers | `.cursor/agents/*-reviewer.md` | Score code |
| Skills | `.cursor/skills/*/SKILL.md` | Named runbooks (`write-adr`, `terraform-plan`, …) |
| Rules | `.cursor/rules/*.mdc` | Attach when you edit matching files |
| Workspace | `petclinic.code-workspace` | Adds the three knowledge folders |

Skills are not assigned in YAML. The architect prompt tells it to read `write-adr`. You can also name a skill in the chat.
