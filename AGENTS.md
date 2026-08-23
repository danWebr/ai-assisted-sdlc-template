<!-- bootstrap:project:start -->
# Project agent instructions

This file is the canonical portable instruction source for Pi, Codex, and compatible agents. Agent-specific files may import or adapt it but must not duplicate its rules.
<!-- bootstrap:project:end -->

## Working agreement

- The human owns product decisions, production approval, and every merge. Agents must never merge pull requests.
- Implementation is human-triggered. Labels such as `ready-for-agent` describe readiness; they never authorize unattended execution.
- Agents may create a focused branch, commit, push, and open a pull request when explicitly implementing approved work.
- Name branches by change type and a short description, such as `feat/x`, `fix/x`, or `chore/x`.
- Use Conventional Commit prefixes such as `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, or `chore:`.
- Keep changes focused. Update relevant tests and documentation with behavior changes.
- Read the nearest `AGENTS.md` before changing a nested project area.
- Run `mise run verify` before handoff. Do not bypass or rename the stable `Verify` contract.

## Repository shape

No application layout is mandatory. When the project has multiple independently deployable applications, prefer `apps/<name>/` with dependencies, configuration, tests, and a local `mise run verify` contract owned by each app. Shared code and other layouts remain project decisions.

## Lifecycle

Use `grill-with-docs` for product discovery, `to-spec` for a human-reviewable specification, `to-tickets` for implementation slices, optional `wayfinder` for unresolved decision fog, explicit `implement` for approved work, `code-review` for the Standards and Spec axes, and `handoff` when another session must continue the work. See `docs/lifecycle.md` for shorter routes.

Use test-driven development at agreed public seams. Prefer behavior tests over implementation-coupled tests. During implementation, run focused tests and typechecking regularly, then the full affected verification suite once at the end.

## GitHub collaboration

GitHub Issues is the supported tracker. Follow `docs/agents/issue-tracker.md` and the canonical labels in `docs/agents/triage-labels.md`; do not guess tracker operations or label meanings.

Feature work targets `dev` and is squash-merged by a human. Production promotion uses a reviewed `dev` to `main` pull request and a merge commit. A hotfix targets `main`, is squash-merged after review, and is then synchronized back into `dev`. Use the production-promotion pull-request template explicitly because GitHub does not select it from the base branch automatically.

Direct pushes, force pushes, deletion, and bypass are prohibited on `dev` and `main`. Both require pull requests and the stable `Verify` check.

## Deployment

GitHub Actions verifies code and never initiates deployment. The deployment provider observes the release branch only after required CI succeeds. Keep development and production secrets and data isolated, review infrastructure changes, and require a tested backup-and-restore path before accepting important production data. See `docs/deployment.md`.
