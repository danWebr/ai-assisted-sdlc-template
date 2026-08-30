# Lifecycle and skill routes

The lifecycle is human-led. Skills structure conversations and produce reviewable artifacts; they do not turn labels or issue state into automatic execution.

## Default path

Most work should use the shortest route that fits:

1. **Clarify only if needed — `grill-with-docs`:** use this when the problem, domain language, or acceptance criteria are still unclear.
2. **Implement — `implement`:** for concrete work, invoke this directly. Its default delivery workflow is defined in [the implement skill](../.agents/skills/implement/SKILL.md); a human reviews and merges the resulting pull request.
3. **Review and ship:** a human reviews and merges the pull request. Use `code-review` separately when reviewing an existing branch or pull request, or when a change needs an explicit second pass.

Use `to-spec` and `to-tickets` only when work spans multiple sessions, contributors, or independently executable slices:

```text
grill-with-docs → to-spec → human review → to-tickets → implement
```

`wayfinder` is an optional planning route for genuinely large efforts with unresolved decisions. It feeds back into `to-spec`; it is not a required stage for ordinary features.

## User-facing workflow entry points

Most users only need these entry points:

| Situation | Start with | What it provides |
| --- | --- | --- |
| Concrete feature or change | `implement` | TDD, reviewed verification, and pull-request handoff |
| Unclear idea or requirements | `grill-with-docs` | A sharper problem, domain language, and decisions |
| Large multi-session effort | `to-spec` | A human-reviewable specification |
| Approved specification | `to-tickets` | Dependency-aware implementation slices |
| Incoming issue or request | `triage` | Clarification, verification, and an agent-ready brief |
| Difficult bug | `diagnosing-bugs` | A tight reproduction loop and regression seam |

The following skills support those routes rather than adding mandatory lifecycle stages:

- `tdd` and `code-review` support implementation and review.
- `domain-modeling` keeps terminology and durable decisions coherent.
- `research` and `prototype` answer questions that cannot be settled from conversation alone.
- `handoff` carries context between sessions.
- `codebase-design` and `improve-codebase-architecture` support architecture work.
- `resolving-merge-conflicts` handles an exceptional repository state.
- `ask-matt` routes an unfamiliar situation to the smallest suitable entry point.

## Repository setup

`mise run bootstrap` performs one-time mechanical personalization only. It confirms the repository identity, records the display name and description in project-facing documentation, stores the non-secret repository identity and Railway intent in `.sdlc/project.conf`, and leaves an uncommitted diff for human review. It does not replace product discovery. `setup-matt-pocock-skills` remains available for later tracker or domain-document reconfiguration, not initial product discovery.

## Human checkpoints

A human approves specifications, chooses tickets, triggers implementation, reviews pull requests, selects the production-promotion template, approves deployment and infrastructure plans, and performs every merge. Agents may prepare branches, commits, pushes, and pull requests but must never merge.
