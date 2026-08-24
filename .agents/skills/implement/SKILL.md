---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Unless the user explicitly requests a different approach, use the default delivery workflow:

1. Choose the delivery branch before editing. When invoked on `dev` for ordinary ticket work, fetch `origin dev` and verify that `origin/dev` resolves; if it does not, stop and report the missing branch. If the working tree is not clean, stop and report the blocking files before changing branches. Fast-forward local `dev` to `origin/dev` with `git merge --ff-only`, then create and switch to a focused branch from `origin/dev`. Use a prefix matching the change type, such as `feat/`, `fix/`, `docs/`, or `chore/`; include `<ticket>-` when a ticket exists, otherwise use `<short-description>`. If the target branch already exists, stop and report it. On an existing non-protected topic branch, stay on that branch and do not silently create a second branch. On `main` or another protected branch, stop unless the user explicitly requests a compatible hotfix or other repository-approved workflow. Never commit or push directly to `dev` or `main`.
2. Implement the work described by the user in the spec or tickets. Use tdd where possible, at pre-agreed seams. Run typechecking and focused tests regularly. Once implementation is ready, use `code-review` against the delivery base (`origin/dev` for the default route, or the explicitly approved base). Address actionable findings before treating the implementation as reviewed.
3. Run `mise run verify` and `git diff HEAD --check` before staging. Stage the reviewed implementation, run `git diff --cached --check`, then commit it with a Conventional Commit. Push the feature branch to `origin` with upstream tracking.
4. Open a pull request from the feature branch to `dev`, using `.github/PULL_REQUEST_TEMPLATE.md` and including the ticket when one exists, summary, verification evidence, operational impact, and agent assistance.
5. Wait for every required pull-request check to complete. For a code or test failure, inspect the failure, make the smallest fix, rerun the affected checks, `mise run verify`, and `git diff HEAD --check`, then stage, commit, push, and wait again. If the failure is infrastructure, permissions, cancellation, or still present after one repair, stop and report it for human intervention. Finish only when every required check has passed; never merge the pull request.

If the user explicitly specifies another base branch, branch strategy, commit-only handoff, pull-request target, or review/CI approach, follow it only when it remains compatible with `AGENTS.md`, protected-branch rules, `mise run verify`/`Verify`, and human review and merge requirements. If it conflicts with those invariants, stop and report the conflict.
