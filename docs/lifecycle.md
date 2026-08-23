# Lifecycle and skill routes

The lifecycle is human-led. Skills structure conversations and produce reviewable artifacts; they do not turn labels or issue state into automatic execution.

## Golden path

1. **Discover — `grill-with-docs`:** stress-test the idea while maintaining domain language and architectural decisions.
2. **Specify — `to-spec`:** synthesize the agreed conversation into a specification labelled `ready-for-human`.
3. **Ticket — `to-tickets`:** after human review, split the specification into dependency-aware, vertical implementation slices labelled `ready-for-agent`.
4. **Map decisions when needed — `wayfinder`:** use only when a large effort still contains decision fog. It resolves decision tickets; it does not build the destination.
5. **Implement — `implement`:** a human selects a ticket and explicitly invokes the skill. The workflow uses TDD at agreed seams where possible, checks the affected project, runs two-axis review, and commits.
6. **Review — `code-review`:** review Standards and Spec separately so conformity cannot hide an incorrect implementation and correctness cannot hide a standards breach.
7. **Handoff — `handoff`:** capture remaining context when another agent session must continue.

`mise run bootstrap` performs one-time mechanical personalization only. It confirms the repository identity, records the display name and description in project-facing documentation, stores the non-secret repository identity and Railway intent in `.sdlc/project.conf`, and leaves an uncommitted diff for human review. It does not replace discovery; the first product-oriented command remains `grill-with-docs`. `setup-matt-pocock-skills` remains available for later tracker or domain-document reconfiguration, not initial product discovery.

## Shorter routes

- **Bug:** `diagnosing-bugs` → agree a regression seam → `tdd` or `implement` → `code-review`.
- **Prototype:** `prototype` → record what was learned → discard or ticket production work separately.
- **Research:** `research` → commit a primary-source Markdown finding → resume the decision it informs.
- **Incoming requests:** `triage` → clarify or verify → prepare an agent-ready brief; triage never triggers implementation.
- **Architecture:** `codebase-design` for interface vocabulary; `improve-codebase-architecture` to find and discuss deepening opportunities.
- **Already concrete work:** invoke `tdd` directly after agreeing the public seam.
- **Unsure which path fits:** invoke `ask-matt`.

## Human checkpoints

A human approves specifications, chooses tickets, triggers implementation, reviews pull requests, selects the production-promotion template, approves deployment and infrastructure plans, and performs every merge. Agents may prepare branches, commits, pushes, and pull requests but must never merge.
