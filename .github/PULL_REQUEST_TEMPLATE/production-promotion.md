# Production promotion: `dev` → `main`

## Included work

<!-- List the issues and pull requests included in this release boundary. -->

## Migrations and configuration

<!-- Database migrations, infrastructure changes, environment values, or "None". Never paste secrets. -->

## Validation

<!-- Record `Verify`, development-environment evidence, and any manual acceptance. -->

## Risk and rollback

<!-- Describe credible failure modes, rollback steps, and data considerations. -->

## Post-deployment checks

<!-- State what a human will verify in production and who owns the check. -->

## Agent assistance

<!-- Name any agent-assisted preparation. Production approval and merge remain human-only. -->

## Human release checklist

- [ ] Base is `main` and head is `dev`.
- [ ] Required `Verify` checks passed.
- [ ] Migrations and configuration changes are reviewed.
- [ ] Rollback and post-deployment checks are actionable.
- [ ] Backup and restore expectations are satisfied for important production data.
- [ ] A human will merge this pull request with a merge commit.
