# GitHub collaboration and release train

GitHub Issues is the supported default tracker. Other trackers can be adapted by replacing `docs/agents/issue-tracker.md`, but their behavior is not tested by this scaffold.

## Issues and triage

Bug and feature forms apply `needs-triage`. Blank issues remain available. Triage uses five roles: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. Wayfinder adds `wayfinder:map`, `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, and `wayfinder:task`.

Specifications use `ready-for-human`; they are not implementation-ready. Tracer-bullet tickets may use `ready-for-agent` after their scope and dependencies are clear. Labels communicate state only. A human must explicitly invoke `implement` for a selected issue.

## Pull requests

Ordinary changes target `dev` and use the default pull-request template. Unless the user explicitly requests a different approach, `implement` starts from the latest `dev` on a focused feature branch, commits and pushes it, opens the pull request, waits for required CI, and fixes failing checks before handoff. The description records the issue, summary, verification evidence, operational impact, and agent assistance. A human reviews and squash-merges each feature branch so the resulting `dev` commit follows Conventional Commits.

Production promotion is a reviewed pull request from `dev` to `main` and uses `.github/PULL_REQUEST_TEMPLATE/production-promotion.md`. GitHub does not automatically choose a template based on the base branch, so the author must explicitly select the production-promotion template, for example with the `template=production-promotion.md` query parameter when opening the pull request. A human uses a merge commit to preserve the release boundary.

A hotfix is reviewed against `main`, squash-merged by a human, then synchronized back into `dev` through a reviewed pull request or by including the mainline commit in the next synchronization change. Never allow the release trains to diverge silently.

Agents may create branches, commits, pushes, and pull requests as part of explicitly requested work. Agents must never merge or issue production approval.

## Branch policy

Rulesets for `dev` and `main` should:

- require pull requests and the status check named `Verify`;
- block direct pushes, force pushes, branch deletion, and administrator bypass;
- permit non-linear history because promotion uses merge commits;
- retain squash merge for feature and hotfix pull requests and merge commits for production promotion.

Repository provisioning installs these rules interactively after showing the complete plan and obtaining human confirmation. It preserves GitHub's default labels and adds, rather than infers, the ten workflow labels above.

## Provisioning

After bootstrap has been reviewed, committed, and pushed to `main`, run `mise run provision` directly in an interactive terminal. The task uses the repository recorded by bootstrap and the existing `gh` session. If Railway was selected during bootstrap, it also uses the existing `railway` session. Install `jq` locally so the task can compare structured platform state; no task installs tools or accepts token arguments.

Provisioning reads current state first and prints one complete mutation plan, including label metadata and the exact ruleset JSON payloads. For Railway it requires an exact workspace ID and, before reusing an existing project, exact project-ID confirmation after dashboard inspection. Nothing is applied unless the owner types the exact confirmation `APPLY`. Cancellation, interruption, and rerun are safe: existing branches, labels, paginated rulesets, workspace-scoped Railway projects, and environments are read before each plan, and non-secret final state is read back after apply.

The GitHub plan creates `dev` from `main`, enables squash and merge commits while disabling rebase merges, and adds or repairs the ten managed workflow labels without removing any other label. Separate active rulesets protect `dev` and `main` with no bypass actors. Both block deletion, force pushes, and direct updates; require pull requests and the `Verify` check; allow only squash on `dev`; and allow merge commits or squash on `main` for promotions and reviewed hotfixes respectively.

Provisioning refuses ambiguous or unsafe existing state instead of deleting it. Resolve duplicate or differently named overlapping release-protection rulesets, duplicate repository-named Railway projects, unexpected Railway environments, or pre-existing Railway application topology manually before retrying.
