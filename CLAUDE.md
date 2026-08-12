# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Wasomi is a Phoenix 1.7 + LiveView e-learning platform: browse a course catalog, pay via Paystack, watch protected video lectures, track progress, and earn certificates. It serves three audiences — anonymous visitors, authenticated learners, and admins managing content/students/payments. Dev server runs on port `4590`.

Deeper documentation already lives in `docs/` and is kept accurate — read the relevant one before making non-trivial changes rather than re-deriving architecture from scratch:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — request flow, directory map, tech stack
- [`docs/DOMAINS.md`](docs/DOMAINS.md) — each context module, its schemas, and key functions
- [`docs/PORTALS.md`](docs/PORTALS.md) — routes grouped by public/learner/admin/webhook
- [`docs/AUTH.md`](docs/AUTH.md) — roles, session flow, `on_mount` hooks, how to add a role
- [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md) — ER diagram and table-by-table constraints
- [`docs/WORKFLOWS.md`](docs/WORKFLOWS.md) — end-to-end flows (buy a course, learn, certificate issuing, payment reconciliation)
- [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) — env vars, per-environment config, required prod secrets
- [`design.md`](design.md) — visual language / Tailwind design tokens; the source of truth for colors is `assets/tailwind.config.js`, reference implementation is `lib/wasomi_web/components/home_components.ex`

`project.md` and `todos.md` are the original product brief and delivery checklist — useful for *why* a feature exists, but may lag behind the actual code; trust the code and `docs/` over them.

## Common commands

```bash
mix setup              # deps, DB create/migrate/seed, asset setup + build (first time)
mix phx.server          # start dev server on :4590
mix test                # create/migrate test DB and run all tests
mix test path/to/test.exs        # single test file
mix test path/to/test.exs:42     # single test at line number
mix format              # format Elixir/HEEx files
mix credo               # static analysis (.credo.exs config)
mix ecto.reset          # drop, recreate, migrate, seed — no aliases block this here, unlike medic/vumbuzi_erp
./scripts/check_linters.sh   # format --check-formatted + credo --strict + test; run before opening a PR
```

Toolchain is pinned via `.tool-versions` (Erlang/OTP 29.0.2, Elixir 1.20.2-otp-29), though `mix.exs` only requires `~> 1.14`.

## Architecture essentials

Context boundary lives under `lib/wasomi/`: `Accounts`, `Catalog`, `Enrollments`, `Payments`, `Learning`, `Certificates`, `Media`, `Notifications`. Web layer is `lib/wasomi_web/`, mostly LiveViews with `WasomiWeb.UserAuth` `on_mount` hooks gating access (`:mount_current_user`, `:ensure_authenticated`, `:ensure_admin`). See `docs/DOMAINS.md` for what each context owns.

**Swappable adapters via config** — three integration points are behind config keys so tests use mocks and dev uses local/demo implementations:

| Config key | Prod/dev | Test (Mox) |
|---|---|---|
| `payment_provider` | `Wasomi.Paystack` | `Wasomi.Payments.ProviderMock` |
| `media_provider` | `Wasomi.Media.Mux` (dev: `Wasomi.Media.Demo`) | `Wasomi.MediaProviderMock` |
| `certificate_storage` | `Wasomi.Certificates.Storage.R2` | `Wasomi.CertificateStorageMock` |
| `certificate_renderer` | (configured separately) | `Wasomi.CertificateRendererMock` |

When touching payments, media playback, or certificate issuance, implement against the behaviour module (`Wasomi.Payments.Provider`, etc.) so both the real adapter and the mock stay in sync.

**Money is stored in minor units** (`price_minor`, `amount_minor`) and formatted through the `money` library / `Catalog.format_price/1` — never do currency math on floats.

**Background jobs run through Oban**: `Wasomi.Payments.Workers.ReconcilePendingPayments` (stale Paystack payments, runs every minute), `Wasomi.Certificates.Workers.IssueCertificate` (enqueued on module/course completion), `Wasomi.Notifications.Workers.DeliverCertificateIssued`.

**Course access is enrollment-gated, not role-gated**: `Wasomi.Enrollments.can_access_course?/2` / `can_access_lecture?/2` check for an `:active` enrollment, independent of the `:learner`/`:admin` role check used for `/admin`.

The repo also contains generated CRUD LiveViews (`*_live/index.ex`, `form_component.ex`, etc.) for every schema. Not all are mounted in `router.ex` — check `docs/PORTALS.md` before assuming a generated screen is reachable; treat unmounted ones as scaffolding.

## Pull request conventions

1. Run `./scripts/check_linters.sh` and fix all failures.
2. Include screenshots or recordings for UI changes (use `N/A` if none).
3. Commit message format: `name/what-pr-does` (e.g. `michael/add-lab-order-filters`).
4. Never add an AI co-author trailer (e.g. `Co-Authored-By: Claude ...`) to commit messages, and never add an AI-generated/attribution footer (e.g. "Generated with Claude Code") to the PR description either.
5. PR descriptions must strictly follow this template — no extra sections, no free-form summaries in place of it:

   ```markdown
   ## Summary

   <!-- What does this PR do and why? One or two sentences. -->

   ## Changes

   <!-- Bullet list of the main changes. -->

   ## How to test

   <!-- Steps a reviewer follows to verify this locally. -->

   1.

   ## Screenshots

   <!-- Add screenshots or screen recordings for UI changes. Use "N/A" if this PR has no visual changes. -->

   ## Checklist

   - [ ] Ran `./scripts/check_linters.sh`
   - [ ] Ran `mix format`
   - [ ] Ran `mix credo`
   - [ ] Ran `mix test` and tests pass
   - [ ] Added/updated migrations and seeds if the schema changed
   - [ ] Updated `README.md` / docs if setup or behavior changed
   - [ ] No secrets or credentials committed

   ## Related issues

   <!-- e.g. Closes #123 -->
   ```
