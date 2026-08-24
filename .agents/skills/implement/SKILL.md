---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Use tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, use code-review to review the work.

Unless the user explicitly requests a different approach, use the default delivery workflow:

1. Prepare ordinary ticket work on a focused branch from the latest `dev`. Fetch `origin/dev` and verify that it resolves. If the working tree is not clean, stop and report the blocking files before changing branches. Create and switch to `feat/<ticket>-<short-description>` from the fetched `origin/dev`; if that branch already exists, stop and report it. When starting on `dev`, fast-forward it to the fetched `origin/dev` before creating the feature branch. Never implement or commit directly on the starting branch, `dev`, or `main` in this default workflow.
2. Run `mise run verify`, commit the reviewed implementation with a Conventional Commit, and push the feature branch to `origin` with upstream tracking.
3. Open a pull request from the feature branch to `dev`, using the repository's ordinary pull-request template and including the ticket, summary, verification evidence, operational impact, and agent assistance.
4. Wait for the pull request's required CI checks to finish. If a check fails, inspect the failure, make the smallest fix, rerun the affected checks and `mise run verify`, commit and push the fix, and wait again.
5. Finish by reporting the pull-request URL and whether all required checks passed. Never merge the pull request.

If the user explicitly specifies another base branch, branch strategy, commit-only handoff, pull-request target, or review/CI approach, follow that instruction instead of this default workflow.
