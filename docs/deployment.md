# Deployment-provider contract

Deployment starts only after the stable `Verify` check succeeds. GitHub Actions does not hold provider tokens and does not initiate deployments; the provider observes the appropriate release branch and owns build and release execution.

Any deployment provider integration must preserve these invariants:

- `dev` deploys only to a development environment and `main` only to production.
- Development and production have distinct secrets, configuration, data, and deployment history.
- Production data is never copied into development for validation.
- Infrastructure mutations use plan-before-apply, require human confirmation, detect existing state, support safe retries, and read back the result.
- Credentials come from the human's authenticated provider tooling or an appropriate external secret store; no platform token is committed.
- Important production data is accepted only after backup and restore have been tested.
- Services, databases, storage, domains, variables, regions, scaling, health paths, and migrations are architectural decisions, not scaffold defaults.

## Railway golden path

Railway is the first-class optional example. Initial provisioning is deliberately limited to one project named after the repository and two isolated environments: `dev` aligned with the `dev` branch, and `prod` aligned with `main`. Environments are isolated configuration and deployment planes; application services and data resources are deferred until architecture is known.

Provisioning uses the owner's existing interactive Railway CLI session. It lists the authenticated workspaces and requires the owner to type the exact workspace ID. If a repository-named project already exists in that workspace, the owner must inspect it in Railway and type its exact project ID before it can be reused. The plan includes both IDs, waits for explicit confirmation, applies the mutations, and verifies the resulting non-secret state. It never guesses or creates application topology. Install and maintain Railway tooling from [Railway's official agent setup](https://agents.railway.com/) rather than vending a Railway skill in this repository.

Railway exposes shared-variable reads as key/value data rather than a metadata-only count. Provisioning therefore never requests shared variables. Before confirming reuse of an existing project, the owner must inspect its `dev`, `prod`, or `production` environments in Railway and confirm that no shared variables exist. The ignored local `.railway/` link created during project initialization contains target context only and must never be committed.

The initial Railway plan creates at most one project named after the repository. Railway creates an initial `production` environment with a new project; provisioning renames it to `prod` and adds `dev`. These empty environments record the release intent `dev` branch to `dev` and `main` branch to `prod`. Source connections and deployment triggers are configured later with the application services because branch triggers do not exist independently of service topology.

### Manual live smoke test

Run this only after the scaffold has been exported into an independent disposable repository, bootstrapped, committed, and pushed. Never run it from the staged artifact inside another repository.

1. Authenticate yourself with `gh auth login` and, when Railway was selected, `railway login`. Do not export or paste tokens into the repository.
2. Run `mise run provision`, compare every listed mutation with `docs/github-workflow.md` and this deployment contract, then cancel. Confirm that GitHub and Railway state did not change.
3. Run it again, type the exact Railway workspace ID, verify the displayed workspace name and ID, then type `APPLY` and inspect the reported read-back result. In GitHub, confirm `dev`, all ten workflow labels, merge settings, and the two active rulesets. In Railway, confirm exactly one repository-named project in the selected workspace, only empty `dev` and `prod` environments, no shared variables, and no services or data resources.
4. Interrupt a disposable run after one or more mutations, rerun, and confirm the next plan contains only missing work and creates no duplicates.
5. Rerun after success and confirm the plan reports no required mutations while read-back verification still succeeds.

If any read-back fails, keep the reported platform state for inspection, correct permissions or unexpected resources manually, and rerun. Provisioning follows every Railway connection page while checking workspace-scoped projects, environments, services, buckets, and volumes. It never requests shared-variable values; their absence remains an explicit dashboard review point when an existing project is confirmed. Databases, domains, regions, source links, and scaling are service topology and are rejected with any pre-existing service. Provisioning never deletes unexpected state to force convergence.

Other providers are compatible only if an adapter implements the same branch alignment, CI gate, isolation, plan/apply, retry, verification, credential, and data-safety contract.
