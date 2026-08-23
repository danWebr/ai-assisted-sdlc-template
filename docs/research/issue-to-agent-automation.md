# Options for executing `ready-for-agent` issues

Research date: 2026-08-23

## Executive summary

For a small repository, there are three credible starting points:

1. **Use a managed GitHub coding agent and keep assignment as the human start signal.** This is the smallest and safest operational change. GitHub Copilot cloud agent and GitHub-supported third-party agents such as OpenAI Codex can be assigned an issue and will work asynchronously, create a pull request, and request human review. This does not provide Pi, but it removes almost all sandbox and orchestration work.
2. **Use a GitHub-hosted Actions job to run Pi headlessly.** This is the smallest custom implementation that preserves Pi. It needs careful separation between the untrusted agent job and a deterministic publisher job, explicit idempotency, a network/filesystem sandbox, and a GitHub App token if the resulting pull request must run CI without manual workflow approval.
3. **Use a webhook, durable queue, and one ephemeral container or VM per issue.** This is the strongest custom foundation once work volume, job duration, resource needs, or security policy outgrow GitHub-hosted Actions. It is materially more work than a small repository needs initially.

A persistent VPS that receives webhooks and executes agents directly on the host is attractive as a prototype but is the weakest long-term boundary. A scheduled poller is useful as a simple prototype or reconciliation backstop, not usually as the primary execution architecture.

The current repository contract must be resolved first. [`AGENTS.md`](../../AGENTS.md), [`docs/github-workflow.md`](../github-workflow.md), and [`docs/agents/issue-tracker.md`](../agents/issue-tracker.md) all say that `ready-for-agent` communicates state only and that a human must explicitly invoke implementation. Therefore, **automatically starting work from the label alone is intentionally non-compliant today**. Either:

- preserve the contract by requiring a second human action (assign the agent, dispatch a workflow, approve an environment gate, or add a separate authorization label); or
- make a deliberate product/governance change so that a maintainer applying `ready-for-agent` is defined as authorization for unattended implementation.

The label also does not mean "executable now": `to-tickets` applies it to independently scoped tickets even when they still have blockers, and reports only the unblocked **frontier** as a candidate for implementation. Any automatic preflight must therefore resolve blocker state, or the trigger should be a separate human action applied only to a frontier ticket.

## Common execution pipeline

Regardless of trigger or compute provider, the robust shape is:

```text
issues:labeled / poll
        |
        v
re-fetch issue and authorize trigger
        |
        v
durable claim keyed by repository + issue
        |
        v
ephemeral executor: clone dev -> run agent -> mise run verify
        |
        v
deterministic publisher: branch -> commit -> push -> PR to dev
        |
        v
human review and merge
```

The executor should not receive credentials that let it merge, approve, deploy, mutate `dev`/`main`, or access production systems. This matches the repository's existing rule that agents may prepare a focused branch and pull request but never merge, and that deployment occurs only after the stable `Verify` check succeeds.

For this repository, the authoritative implementation prompt should be the structured **Agent Brief** posted by triage, not an undifferentiated concatenation of the issue body and every comment. The brief already defines desired behavior, interfaces, acceptance criteria, and scope boundaries. Re-fetch it from GitHub, verify that it was posted by an authorized actor before the ticket became ready, and pass the remaining discussion only as clearly delimited, non-authoritative context if it is needed at all.

## Options and estimated effort

Estimates are focused engineer-days for a small repository with an existing deterministic `mise run verify`, excluding ongoing prompt/model tuning. “Hardened” means retry behavior, idempotency, timeouts, audit logs, least-privilege credentials, cleanup, and a tested failure path—not a general multi-tenant service.

| Option | Proof of concept | Small-repo hardened version | Ongoing operations | Best fit |
| --- | ---: | ---: | --- | --- |
| Managed coding agent; human assigns issue | 0.5–1 day | 1–2 days | Very low | Lowest-effort recommendation when Pi is not required |
| Thin Action that assigns a managed agent on the label | 1–2 days | 2–4 days | Low | Label automation with managed execution; preview API/auth trade-offs |
| GitHub Agentic Workflows (`gh-aw`) | 1–3 days | 3–6 days | Low | GitHub-native agent workflow with stronger write separation; currently preview |
| GitHub-hosted Action running Pi | 1–2 days | 4–7 days | Low | Best first custom Pi implementation |
| Scheduled Action/VPS poller running Pi | 1–2 days | 3–6 days | Low–medium | Simplest trigger and useful reconciliation path; delayed |
| VPS webhook service + local containers | 2–4 days | 7–12 days | Medium–high | A few private repos, custom runtime, willingness to operate a service |
| Webhook + queue + managed ephemeral jobs | 4–7 days | 10–20 days | Medium | Strong custom isolation/reliability or several repositories |
| Ephemeral self-hosted Actions runners / ARC | 7–15 days | 15+ days | High | Existing Kubernetes/platform team or special hardware/network needs |

Model inference is normally the dominant variable cost. Compute cost is usage-based for GitHub-hosted private-repository jobs and managed container jobs; a VPS costs money while idle as well as while executing. Standard GitHub-hosted runners are free and unlimited for public repositories; private repositories use included minutes and then per-minute billing ([GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)).

## 1. Managed coding agents

### Human assignment as the start signal

GitHub Copilot cloud agent can be assigned an issue, starts working on a pull request, and requests review when finished. Assignment always creates a pull request; the agent receives the issue title, description, and comments that exist at assignment time ([GitHub: kick off a cloud-agent task](https://docs.github.com/en/copilot/how-tos/copilot-on-github/use-copilot-agents/kick-off-a-task)). GitHub also supports third-party coding agents, currently including OpenAI Codex and Anthropic Claude, through the same asynchronous issue/PR workflow ([GitHub: third-party coding agents](https://docs.github.com/en/copilot/concepts/agents/about-third-party-coding-agents)).

This is the closest off-the-shelf match to the desired outcome. The human can apply `ready-for-agent` during triage and later assign the selected agent; assignment is the explicit start signal and therefore preserves the repository's current working agreement.

Security controls are substantially stronger than a naive custom runner: GitHub says cloud-agent work is limited to one agent branch, draft pull requests require human review and merge, the triggering user cannot approve the resulting PR, and CI is approval-gated by default. Internet access is firewalled, although GitHub documents limitations and bypass potential, so it is still not a complete security boundary ([risks and mitigations](https://docs.github.com/en/copilot/concepts/agents/cloud-agent/risks-and-mitigations), [firewall limitations](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-the-firewall)).

The trade-offs are vendor coupling, less control over the executor, paid-plan/usage requirements, and no Pi runtime. Managed agent sessions consume GitHub Actions minutes and AI usage credits ([Copilot billing](https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-copilot/about-billing-for-github-copilot)).

### Automatically assign a managed agent from the label

A small `issues: [labeled]` Action could call GitHub's assignment API when `github.event.label.name == 'ready-for-agent'`. GitHub's agent-task and issue-assignment APIs are currently public preview. They require a **user token**—a personal access token, OAuth token, or GitHub App user-to-server token; server-to-server installation tokens are not supported for the agent-tasks API. The documented fine-grained token permissions for assigning Copilot include read/write Actions, contents, issues, and pull requests ([GitHub: cloud agent via API](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/use-cloud-agent-via-the-api)).

This is easy to build but has two caveats: it changes the repository's authorization semantics, and its long-lived/user-scoped authentication is less attractive than an installation token for unattended backend automation. Prefer manual assignment unless automatic assignment has real workflow value.

### GitHub Agentic Workflows

GitHub Agentic Workflows (`gh-aw`) compile a Markdown agent workflow into a locked GitHub Actions workflow. They support GitHub Copilot, OpenAI Codex, Anthropic Claude, and Google Gemini engines and are currently public preview ([GitHub: Agentic Workflows](https://docs.github.com/en/copilot/concepts/agents/about-github-agentic-workflows)). They are distinct from assigning a managed coding agent.

For this use case, `gh-aw` can react to an issue-label event, modify a checkout, and declare `create-pull-request` as its only write output. Its security model is valuable: the agent runs read-only and proposes structured outputs; a separate permission-controlled job performs the validated write. The framework also protects sensitive files and can stage outputs for review before enabling writes ([safe outputs](https://github.github.com/gh-aw/reference/safe-outputs/), [pull-request safe output](https://github.github.com/gh-aw/reference/safe-outputs-pull-requests/)).

This is a compelling middle ground if preview software is acceptable. It is more constrained and easier to audit than a handwritten Pi workflow, but it does not currently list Pi as an engine. Pull requests opened or updated with the default `GITHUB_TOKEN` now create `pull_request` workflow runs in an approval-required state. A human with write access can approve those runs; use a GitHub App or appropriately scoped token only when CI must start without that approval ([`GITHUB_TOKEN` behavior](https://docs.github.com/en/actions/concepts/security/github_token), [triggering CI](https://github.github.com/gh-aw/reference/triggering-ci/)).

## 2. GitHub-hosted Actions running Pi

GitHub Actions has an exact event for this trigger:

```yaml
on:
  issues:
    types: [labeled]

jobs:
  implement:
    if: github.event.label.name == 'ready-for-agent'
```

The workflow file must exist on the repository's default branch for `issues` events to trigger ([GitHub Actions events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows), [label-condition example](https://docs.github.com/en/actions/tutorials/manage-your-work/add-comments-with-labels)). In this repository, ordinary changes target `dev`, so the job must explicitly fetch and branch from current `dev`; the event's SHA/ref points at the default branch, not necessarily the intended implementation base.

Pi supports non-interactive print/JSON modes, ephemeral sessions with `--no-session`, explicit model/provider selection, and a tool allowlist. That makes `pi -p --no-session ...` suitable for a one-shot worker. Pi deliberately has no built-in permission prompts and recommends running in a container or building a confirmation flow; extensions run with full system permissions. Project-local configuration also has an explicit trust flow ([Pi README and CLI reference](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/README.md), [Pi extension security](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md)). Pi provides a sandbox **example** based on OS-level filesystem/network restrictions, but it is not a default guarantee ([Pi sandbox extension example](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/examples/extensions/sandbox/index.ts)).

A defensible implementation should use at least two jobs:

1. **Agent job:** fresh GitHub-hosted VM; repository read token only; provider API key; Pi and project packages pinned; no deploy credentials; external sandbox policy baked outside the checkout; produce a patch and verification log.
2. **Publisher job:** no model/provider key; short-lived GitHub write token; validate expected branch/base/path limits; apply the patch; commit with a deterministic branch name; push; open a PR to `dev`; never merge.

GitHub-hosted jobs run in clean ephemeral VMs, which prevents persistence into the next job, while GitHub warns that self-hosted runners can remain compromised by untrusted workflow code ([GitHub Actions secure use](https://docs.github.com/en/actions/reference/security/secure-use)). Ephemerality does **not** stop code inside the current job from reading secrets made available to that job or exfiltrating them over the network. Issue text and repository files must be treated as untrusted agent input. The provider key is the unavoidable high-value secret in the agent job; all unrelated secrets should stay out.

The built-in `GITHUB_TOKEN` is unique per job and repository-scoped. Set explicit least-privilege permissions because unspecified permissions become `none` once any are declared ([workflow token permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)). Repository settings must also allow Actions to create pull requests. Most events caused by `GITHUB_TOKEN` do not recursively start workflows, but pull requests opened or updated with it now create approval-required `pull_request` workflow runs. This repository can therefore use `GITHUB_TOKEN` for an MVP and have a maintainer approve the stable `Verify` run. Use a narrowly installed GitHub App token only if CI must start automatically, rather than a broad personal token ([`GITHUB_TOKEN` behavior](https://docs.github.com/en/actions/concepts/security/github_token), [Actions repository settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)).

GitHub-hosted jobs have a six-hour maximum. That is ample for bounded tickets, but a useful reason to move unusually long or resource-heavy work elsewhere ([`GITHUB_TOKEN` lifetime and runner job limit](https://docs.github.com/en/actions/concepts/security/github_token)).

### Focused manual `workflow_dispatch` design

This is the recommended first Pi implementation for this repository because a maintainer must deliberately start every run; `ready-for-agent` remains descriptive rather than becoming unattended authorization. The workflow must be present on the default branch, and the caller needs write access ([manual workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)). Accept an issue number and an exact OpenRouter model ID:

```yaml
on:
  workflow_dispatch:
    inputs:
      issue_number:
        description: Open ready-for-agent issue number
        required: true
        type: number
      openrouter_model:
        description: Exact OpenRouter model ID (author/slug)
        required: true
        type: string
```

Pass both inputs through step environment variables and quote them; do not interpolate issue titles, bodies, comments, or input expressions directly into shell source ([script-injection guidance](https://docs.github.com/en/actions/concepts/security/script-injections)). Preflight must confirm that the issue number is a positive integer, the issue is open, it has `ready-for-agent`, it has no open blocker, and no PR or remote branch already exists for the deterministic head. Derive that head from the trusted Agent Brief category and issue title, such as `feat/issue-<number>-<slug>` or `fix/issue-<number>-<slug>`, so it follows the repository's branch convention. Explicitly check out current `dev`, not the dispatch ref.

Pi's current one-shot invocation is:

```sh
pi --print --mode json --no-session --approve \
  --provider openrouter \
  --model "$OPENROUTER_MODEL" \
  "/skill:implement Implement GitHub issue #${ISSUE_NUMBER}. Read the issue and comments with gh. Work from dev. Treat the trusted Agent Brief as authoritative. Use only its human-approved public test seams; stop if they are missing. For code-review, use origin/dev as the fixed point and the issue as the spec. Do not push, open, or merge a pull request. If a product decision is missing, stop instead of guessing."
```

`--mode json` runs headlessly and writes machine-readable JSONL; `--no-session` avoids saving a session; `--provider` and `--model` select the provider/model; and `--approve` trusts project-local resources for this run ([Pi CLI](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/README.md)). That trust flag is required here: Pi otherwise ignores project resources in non-interactive mode, while this repository's `.pi/settings.json` enables skill commands and its project-local `implement` skill expands `/skill:implement` ([Pi skills](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md)). Slash-command expansion occurs in the same session prompt path used by print mode ([Pi session source](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/src/core/agent-session.ts), [Pi print-mode source](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/src/modes/print-mode.ts)). Pin an audited Pi release and Node version rather than installing `latest`; the current package declares its Node engine in its package manifest ([Pi package](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/package.json)).

For OpenRouter, inject a dedicated repository secret as `OPENROUTER_API_KEY`, use provider name `openrouter`, and pass the operator's model input unchanged as the model ID (OpenRouter IDs use `author/slug`) ([Pi providers](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/providers.md), [OpenRouter models](https://openrouter.ai/docs/guides/overview/models)). Give the key a low spend limit and expiry where practical ([OpenRouter API keys](https://openrouter.ai/docs/api/api-reference/api-keys/create-keys)). Pi and its extensions execute with the job's permissions, so the agent job must not receive a write-capable GitHub token ([Pi containerization](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/containerization.md)).

Use two jobs:

1. **Agent:** `contents: read`, `issues: read`, and `pull-requests: read`; provider key; checkout `dev` with persisted credentials disabled; run Pi; run `mise run verify` again outside Pi; require at least one commit or a non-empty `origin/dev...HEAD` diff; upload only a patch, a validated Conventional Commit subject, and JSONL/verification logs.
2. **Publisher:** runs only after agent success; `contents: write` and `pull-requests: write`; no provider key; fresh checkout of the captured `dev` base; recheck branch/PR absence; apply the patch; run `mise run verify` again before exposing any Git write credential to a shell step; validate the subject against `^(feat|fix|docs|test|refactor|chore): .+`; commit; push without force; and run `gh pr create --base dev --head <derived-head> --body-file ...`. The body should follow this repository's PR template, link/close the issue, record verification, and state agent assistance. It must never call a merge command ([checkout credentials and refs](https://github.com/actions/checkout/blob/main/README.md), [`gh pr create`](https://cli.github.com/manual/gh_pr_create)).

Set workflow concurrency to `agent-${{ github.repository_id }}-issue-${{ inputs.issue_number }}` with cancellation disabled. The deterministic branch, preflight lookup, publisher recheck, and non-force push make duplicate/racing runs fail closed. A rerun should report the existing branch/PR instead of overwriting it; retry requires deliberate cleanup or a later explicit attempt mechanism. Set a job timeout and make agent failure, unresolved model, no diff, dirty tree, verification failure, or cancellation prevent publication. Upload diagnostic logs with `if: always()` and report failure in the Actions summary; avoid issue comments in the MVP so no job needs `issues: write` ([Actions concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)).

With repository PR creation enabled, the publisher can use `GITHUB_TOKEN`. The resulting PR's `Verify` run will wait for a maintainer's approval, which is compatible with the required human-review gate. A GitHub App token is an optional later improvement only if automatic CI is worth removing that approval click.

## 3. VPS webhook service

A GitHub App installed only on selected repositories is the correct backend identity. GitHub Apps start with no permissions; request only the permissions needed to read issues/code and create a branch/PR. Installation access tokens are repository/permission scoped and expire after one hour, and they can authenticate HTTP Git operations when the App has Contents permission ([choosing App permissions](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app), [installation authentication](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation)). Do not build this around an owner's classic PAT.

The public endpoint must:

- validate `X-Hub-Signature-256` against a high-entropy webhook secret before parsing/processing;
- accept only the `issues` event with action `labeled` and the exact label;
- record `X-GitHub-Delivery` as a replay/idempotency key;
- respond within ten seconds and enqueue work rather than running Pi in the request handler.

These are GitHub's documented webhook practices ([signature validation](https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries), [webhook best practices](https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks)). GitHub does not automatically retry failed webhook deliveries, so the service needs monitoring plus a scheduled redelivery/reconciliation path ([failed deliveries](https://docs.github.com/en/webhooks/using-webhooks/handling-failed-webhook-deliveries)).

For a prototype, the queue can be a database table and the worker can start a short-lived rootless container. Do not run Pi directly in the long-lived webhook process or mount the Docker daemon socket into the agent container. Enforce CPU/memory/time/process limits, a disposable workspace, read-only host filesystem, narrowly allowed network egress, and cleanup on success, failure, cancellation, and reboot. Store GitHub App and model credentials in an external secret store and mint the installation token only when publishing.

The operational burden is the important cost: HTTPS and certificate renewal, OS/container updates, webhook health, queue recovery, disk cleanup, log retention, backups for the job ledger, resource exhaustion, and alerting. A single fixed VPS also limits concurrency and remains one compromise/failure domain.

## 4. Webhook + queue + managed ephemeral execution

This keeps the GitHub App receiver very small and pushes each claimed issue to a durable queue. A worker then creates one disposable execution environment—for example a Cloud Run Job, AWS Fargate task, or short-lived VM—per issue. Cloud Run Jobs are designed to run container tasks to completion, support timeouts and retries, and charge only while a task executes ([Cloud Run Jobs](https://cloud.google.com/run/docs/create-jobs)). AWS documents a separate isolation boundary per Fargate task that does not share the underlying kernel, CPU, memory, or network interface with another task ([AWS containers whitepaper](https://docs.aws.amazon.com/pdfs/whitepapers/latest/containers-on-aws/containers-on-aws.pdf)).

This design gives better isolation and burst handling than a worker on the webhook VPS, at the cost of container-image maintenance, cloud IAM, queue/dead-letter configuration, log aggregation, and more moving parts. It becomes worthwhile when there are several repositories, parallel tickets, long jobs, special machine sizes, or a stricter boundary between agent executions.

Queue delivery must be assumed duplicate. For example, Amazon SQS standard queues provide at-least-once delivery and explicitly require idempotent consumers ([SQS delivery](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/standard-queues-at-least-once-delivery.html)). The same defensive rule should be used with every trigger mechanism.

## 5. Scheduled poller

A poller can run in GitHub Actions on a schedule or under cron/systemd on a VPS. It lists open issues with `ready-for-agent`, ignores pull requests returned by the Issues API, and claims eligible issues that have no active/completed execution. The REST Issues endpoint supports filtering by labels and `since` timestamps ([GitHub Issues REST API](https://docs.github.com/en/rest/issues/issues)). Authenticated GitHub App installations start with a 5,000-request-per-hour REST limit, far above a small repository's polling needs ([REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)).

The benefit is that no inbound service or webhook recovery is needed, and every scan naturally reconciles missed work. The disadvantages are latency and weaker event semantics: a scan sees current state, not necessarily the precise label transition. Persist a cursor/job ledger and use the same durable claim as the webhook design.

Scheduled Actions run from the latest default-branch commit, have a five-minute minimum interval, and public-repository schedules are disabled after 60 days without repository activity ([scheduled workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)). A 5–15 minute polling delay is normally irrelevant for ticket implementation.

## 6. Self-hosted GitHub Actions runners

Putting a standard self-hosted runner daemon on a VPS is easy but combines the risks of a persistent worker with the write surface of GitHub Actions. GitHub says self-hosted runners do not guarantee clean ephemeral VMs, may be persistently compromised by untrusted code, and should almost never be used for public repositories ([secure use](https://docs.github.com/en/actions/reference/security/secure-use)). A private repository is not automatically safe if people with read/fork access can cause code to run.

If self-hosting is necessary, provision a fresh ephemeral runner per job and destroy its host after one use. GitHub recommends ephemeral rather than persistent runners for autoscaling and documents just-in-time registration; Actions Runner Controller (ARC) is the recommended Kubernetes solution ([self-hosted runner autoscaling](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)). This is disproportionate for one small repository unless Kubernetes, image building, monitoring, and log forwarding already exist.

## Concurrency, idempotency, and lifecycle details

Every option needs the following controls:

1. **Re-fetch before starting.** Confirm the issue is open, still has `ready-for-agent`, is an implementation ticket rather than a PR, has no open blockers, and targets this repository.
2. **Authorize the actor/action.** If the label becomes an authorization signal, confirm it was applied by an allowed maintainer role. Avoid treating arbitrary issue text or comments as authorization.
3. **Claim durably.** Use a database unique constraint for custom infrastructure. In Actions, use a concurrency group such as `agent-${{ github.repository_id }}-${{ github.event.issue.number }}` with `cancel-in-progress: false`, plus a durable external or GitHub-visible claim. Actions concurrency guarantees one running member of a group but pending runs may be replaced depending on queue configuration, so it is not a complete execution ledger ([Actions concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)).
4. **Use deterministic identities.** Branch `feat/issue-<number>-<slug>` and a PR body marker such as `Agent-Job: <repo-id>:<issue-number>:<attempt>`. Before publishing, search for that marker or head branch. A rerun should update or report the existing PR, never create a second one silently.
5. **Distinguish redelivery from retry.** A webhook redelivery has the same `X-GitHub-Delivery`; a deliberate remove/re-add of the label receives a new delivery. Decide whether re-labeling retries the failed attempt or starts a new attempt, and record that policy.
6. **Bound concurrency globally and per repository.** Start with one agent at a time. It reduces API/model spend and avoids branches racing over the same base. Increase only after the publish path is proven idempotent.
7. **Make failure visible.** Comment or check-run with one of: rejected preflight, claimed/running, verification failed, PR opened, needs human input, or infrastructure failure. Never remove evidence when retrying.
8. **Stop at a PR.** Target `dev`, run `mise run verify`, record evidence in the PR template, and leave merge and production approval to a human.

## Recommended incremental route

### If Pi is optional

Keep `ready-for-agent` as readiness and use **human issue assignment to a managed coding agent** as authorization. Trial several bounded tickets, verify that `AGENTS.md`, skills, `dev` targeting, `mise run verify`, and the PR template are followed, then decide whether automatic label-to-assignment saves enough work to justify preview APIs and user-scoped authentication.

### If Pi is required

Start with a **manually dispatched GitHub-hosted Action** that accepts an issue number. This tests non-interactive Pi, the pinned runtime, sandbox policy, verification, branch/PR publication, and failure reporting without changing label semantics. Once it is reliable:

1. add the `issues:labeled` trigger but leave an environment approval or explicit authorization gate;
2. test idempotent reruns and label redelivery;
3. only then decide whether applying `ready-for-agent` itself should authorize execution and update the repository contract accordingly.

Move to webhook + queue + managed ephemeral jobs only when Actions' duration/resources, preview constraints, concurrency, or security posture become a demonstrated limitation. Avoid ARC and a persistent self-hosted runner for the initial small-repository implementation.
