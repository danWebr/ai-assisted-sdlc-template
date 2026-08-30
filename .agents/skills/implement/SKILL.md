---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Follow `AGENTS.md` and any compatible workflow override from the user.

Choose the delivery route before editing. Ordinary work starts from the latest `origin/dev` and targets `dev`; approved hotfixes start from `origin/main` and target `main`. Stay on an existing topic branch. Otherwise require a clean tree and an unused, focused branch name. Stop on a missing base, detached HEAD, or unapproved protected branch. Never commit or push directly to a protected branch.

Implement the requested behavior. Use tdd at agreed seams. Run focused tests and typechecking regularly.

Run `mise run verify` and `git diff --check` on the worktree, index, and delivery range. Make a candidate Conventional Commit, then use `code-review` on `<delivery-base>...HEAD` against the ticket or spec. State when no spec exists. Fix and repeat until no actionable findings remain.

Unless this is a commit-only handoff, push the branch and open a pull request with `.github/PULL_REQUEST_TEMPLATE.md`. Include the ticket, summary, verification evidence, operational impact, and agent assistance.

Wait for all required checks. Repair one non-infrastructure failure through the same verification and review cycle. Stop on infrastructure failures or a failed repair. Finish only when all checks pass. Never merge the pull request.
