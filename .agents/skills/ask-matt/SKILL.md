---
name: ask-matt
description: Ask which skill or flow fits your situation. A router over the skills in this repo.
disable-model-invocation: true
---

# Ask Matt

You do not need to remember every skill. Start with the smallest entry point that fits the work.

## Default route

Most work follows one of these paths:

1. **The work is concrete** → invoke **`implement`** directly. It drives TDD where practical, runs verification, and closes out the implementation checks.
2. **The idea or requirements are unclear** → use **`grill-with-docs`**, then return to **`implement`**.
3. **The work spans multiple sessions or contributors** → use **`grill-with-docs`**, then **`to-spec`**, human review, **`to-tickets`**, and **`implement`** per approved slice.

`wayfinder` is only for genuinely large efforts where important decisions remain unresolved. When its map is clear, it hands back to `to-spec`; it does not replace the implementation route.

## Incoming work

- **Bugs and requests piling up** → **`triage`**. It clarifies and verifies incoming work, then prepares a brief for explicit human-triggered implementation.
- **Something is difficult to reproduce or diagnose** → **`diagnosing-bugs`**. It establishes a tight runnable signal before proposing a regression seam and fix.

## Supporting routes

- **A runnable answer is needed** → **`prototype`** for throwaway state or UI exploration.
- **Primary-source reading is needed** → **`research`**, then bring the result back into the relevant decision or implementation conversation.
- **The codebase needs architectural exploration** → **`improve-codebase-architecture`**; use **`codebase-design`** when designing a chosen seam.
- **A session must continue elsewhere** → **`handoff`**.
- **A merge or rebase is conflicted** → **`resolving-merge-conflicts`**.

## Supporting vocabulary

These skills are normally used by the routes above rather than treated as separate lifecycle stages:

- **`grilling`** and **`domain-modeling`** sharpen the problem and its language.
- **`tdd`** drives behavior-first implementation at an agreed public seam.
- **`code-review`** reviews an existing change across Standards and Spec axes.

The repository already configures GitHub Issues, triage labels, and a single-context domain layout. Use `setup-matt-pocock-skills` only when intentionally reconfiguring those choices.
