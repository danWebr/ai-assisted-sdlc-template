<!-- bootstrap:project:start -->
# AI-assisted SDLC template

A personal, public starting point for human-led, AI-assisted software development.
<!-- bootstrap:project:end -->

Pi is the tested primary runtime. Codex and Claude Code can reuse the same canonical instructions and skills through the compatibility paths documented in [Agent compatibility](docs/agent-compatibility.md). The workflow is opinionated and does not promise broad platform support.

<!-- bootstrap:template-onboarding:start -->
## Create a project from this template

1. Complete the tested [macOS golden-path setup](docs/agent-compatibility.md#macos-golden-path-setup), or review the stated adaptations for another platform.
2. Create a repository from this GitHub template and clone that new repository. Do not work in the canonical template repository.
3. Run `mise run verify`, then run `mise run bootstrap` and confirm the inferred repository identity.
4. Review the uncommitted personalization diff, then commit and push the initial `main` branch manually.
5. Run `mise run provision`, review the complete GitHub and optional Railway mutation plan, and type `APPLY` only when it is correct.
6. Start Pi, review its project-package trust prompt, and continue with the project-local guidance written into the personalized README.

Canonical-template maintenance notes live in [Template maintainer onboarding](docs/template-maintainer-onboarding.md). Bootstrap removes this template-only section and that maintainer document from generated projects.
<!-- bootstrap:template-onboarding:end -->

## Engineering workflow

This repository packages a portable engineering lifecycle, project-local skills, GitHub collaboration defaults, a stable verification interface, and deployment policy without choosing a product domain, application stack, or repository layout. Review `AGENTS.md`, `.pi/settings.json`, and the project-local skills before trusting the repository in Pi. Product discovery begins with `/skill:grill-with-docs`; implementation remains human-triggered with `implement`.

## Guides

- [Lifecycle and skill routes](docs/lifecycle.md)
- [GitHub collaboration and release train](docs/github-workflow.md)
- [Verification contract](docs/verification.md)
- [Agent compatibility and supported platforms](docs/agent-compatibility.md)
- [Deployment-provider contract](docs/deployment.md)
- [Angular, FastAPI, and PostgreSQL blueprint](docs/blueprints/angular-fastapi-postgresql.md)
- [Skill provenance and local customizations](docs/skills.md)

## Initial scope

The initial repository contains no application, infrastructure topology, environment values, credentials, or deployment state. An independently deployable `apps/` layout is recommended when it fits the project; it is not required.

Licensed under the [MIT License](LICENSE).
