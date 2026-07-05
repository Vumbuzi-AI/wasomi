# Wasomi

Wasomi is a Phoenix learning platform for selling and delivering online courses. It serves public visitors browsing the catalog, learners taking paid courses, and administrators managing content, students, videos, and payments.

Major areas:

- Public website and course catalog at `/`, `/landing`, `/courses`, and `/courses/:slug`
- Learner portal for dashboard, courses taken, course player, certificates, checkout, and receipts
- Admin portal at `/admin` for courses, students, payments, and lecture video uploads
- Paystack payment callbacks and webhooks

## Prerequisites

- Elixir `~> 1.14` as required by `mix.exs`
- Erlang/OTP compatible with the installed Elixir version
- PostgreSQL, using the local dev credentials in `config/dev.exs`
- Node/npm for the Phoenix asset pipeline in `assets/`

There is no `.tool-versions` file in this repo, so exact local tool pins are not committed.

## Setup

The app has one-command setup aliases:

```sh
mix setup
```

This runs `deps.get`, creates and migrates the database, runs `priv/repo/seeds.exs`, installs Tailwind/esbuild, and builds assets.

Development database defaults:

- database: `wasomi_dev`
- username: `postgres`
- password: `postgres`
- host: `localhost`

## Run

```sh
mix phx.server
```

Open http://localhost:4590.

## Seeded Logins

| Role    | Email                 | Password        | Notes                                                                        |
| ------- | --------------------- | --------------- | ---------------------------------------------------------------------------- |
| Admin   | `admin@wasomi.test`   | `password12345` | Redirects to `/admin` after login.                                           |
| Learner | `student@wasomi.test` | `student12345`  | Has an active enrollment and successful payment for the first seeded course. |

Seeds also create six published courses with modules and playable demo HLS lectures.

## Common Commands

```sh
mix setup          # install deps, setup DB, seed data, and build assets
mix ecto.setup     # create DB, migrate, and seed
mix ecto.reset     # drop DB, recreate, migrate, and seed
mix phx.server     # run the dev server on port 4590
mix test           # create/migrate test DB and run tests
mix format         # format Elixir files
mix credo          # static analysis
mix assets.build   # build Tailwind and esbuild assets
mix assets.deploy  # minified assets and phx.digest for release builds
```

`mix ecto.reset` is destructive because it drops the local database. There are no custom aliases that intentionally block destructive operations.

## Opening a Pull Request

Before opening a pull request:

1. Run `./scripts/check_linters.sh` and fix any formatting, Credo, or test failures.
2. Fill out the pull request summary, changes, and how-to-test sections.
3. Add screenshots or screen recordings for UI changes. Use `N/A` when there are no visual changes.
4. Complete the pull request checklist, including docs, migrations, seeds, and secrets checks when relevant.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Domains](docs/DOMAINS.md)
- [Portals and Routes](docs/PORTALS.md)
- [Authentication and Authorization](docs/AUTH.md)
- [Data Model](docs/DATA_MODEL.md)
- [Workflows](docs/WORKFLOWS.md)
- [Environment](docs/ENVIRONMENT.md)
