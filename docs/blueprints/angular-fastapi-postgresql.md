# Angular, FastAPI, and PostgreSQL integration blueprint

This is an explanatory starting point for a future agent conversation. It generates no application and provisions no infrastructure.

## Suggested shape

An independently deployable layout could use:

```text
apps/
├── frontend/   # Angular application, local dependencies, tests, mise.toml
└── backend/    # FastAPI application, migrations, tests, mise.toml
```

The layout is a recommendation, not an invariant. A single application, library, CLI, monorepo, or different directory scheme can keep the same lifecycle and root verification contract.

## Boundaries

The Angular app owns browser behavior and its build artifact. The FastAPI app owns the HTTP API, domain behavior, persistence boundary, and database migrations. PostgreSQL is an application resource chosen during architecture, not a template dependency. Each app exposes `mise run verify`; the root `mise run verify` composes them behind the stable GitHub check.

For Railway, a later architecture ticket may choose separate frontend and backend services plus a PostgreSQL service in each environment. Development resources belong only to `dev`; production resources belong only to `prod`. Service names, variables, regions, health checks, start commands, migration strategy, scaling, domains, and backup policy must be decided and reviewed for the project rather than copied from this blueprint.

## Suggested agent starting point

After discovery and an approved specification, ask an agent to propose the smallest vertical slice that crosses Angular, FastAPI, and PostgreSQL through public interfaces. Agree the browser/API seam and persistence behavior before TDD. Require app-local tests, typechecking, migration review, root verification, and a deployment plan that proves environment isolation and restore expectations. Do not ask the scaffold to generate the stack wholesale.
