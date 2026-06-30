# Wasomi — Delivery To-Do

Working checklist to take Wasomi from the current scaffold to the v1 proof of
concept described in [`project.md`](project.md). Visual work follows
[`design.md`](design.md). Check items off as they land.

---

## Where we are now ✅

- **Data model generated.** All 8 schemas + migrations exist: `users` (+ auth
  tables), `courses`, `modules` (`CourseModule`), `lectures`, `enrollments`,
  `payments`, `lecture_progress`, `certificates`.
- **Contexts exist but are plain CRUD** (`Catalog`, `Enrollments`, `Payments`,
  `Learning`, `Certificates`, `Accounts`) — generated `list_/get_/create_/
  update_/delete_` only. No domain logic yet.
- **Auth done** via `phx.gen.auth` (User, tokens, session controller,
  `UserAuth`, registration/login/reset/confirm LiveViews).
- **Default CRUD LiveViews generated** for every schema — but **not wired into
  the router** (only `/`, `/landing`, and auth routes are live).
- **Marketing home page** (`HomeLive`, `home_components.ex`) + Tailwind design
  system in place.

> ⚠️ Gaps to be aware of: Phoenix is **1.7.19** (project.md targets 1.8);
> password hashing is **bcrypt**, not Argon2; no `phone` field / role on User
> yet; **Oban, ex_money, ChromicPDF, R2/ex_aws, an HTTP client, and Mox are not
> installed**. The generated CRUD LiveViews are scaffolding, not the real
> learner flows.

---

## Phase 0 — Foundations & dependencies

- [ ] Add deps: `oban`, `ex_money` (or `money`), `req` (HTTP client for
      providers), `chromic_pdf`, `ex_aws` + `ex_aws_s3` (R2), `mox` (test),
      optionally `sentry`/`appsignal`.
- [ ] Configure **Oban** (repo, queues: `payments`, `certificates`, `mailers`,
      `default`) + migration for Oban tables.
- [ ] Add runtime config/secrets scaffolding in `runtime.exs` for Paystack,
      video provider, R2, and mail provider keys.
- [ ] Decide & document: keep bcrypt or switch to Argon2 (project.md §13).
- [ ] Confirm migrations run cleanly (`mix ecto.reset`).

## Phase 1 — Accounts hardening

- [x] Add `phone` (normalised `2547XXXXXXXX`) and `role` (`learner` | `admin`)
      to `users` (migration + changeset + validation).
- [x] Capture & normalise phone in registration; validate MSISDN format.
- [x] Add `require_admin` / role-based `on_mount` + plug for admin routes.
- [x] Welcome email on confirmation (wire to Notifications, Phase 8).

## Phase 2 — Catalog (course structure)

- [x] Flesh out `Catalog` API: published-course queries, ordered modules &
      lectures, slug lookup, pricing helpers (ex_money).
- [x] Add fields/validations per data model: `slug` (unique), `status`
      (draft/published), `position`, `price_minor`, `currency`, ordering
      uniqueness (`course_id+position`, `module_id+position`).
- [x] Public **course catalog** LiveView (list published courses) — design.md.
- [x] Public **course detail / landing** LiveView (modules, lectures preview,
      price, enroll CTA).
- [x] `priv/repo/seeds.exs`: seed the first course _"The Human Stack"_ with its
      6 modules + lectures.

## Phase 3 — Enrollments (THE pay-gate) 🔒

- [x] `Enrollments` API: `enrolled?/2`, `active_enrollment/2`,
      `can_access_course?/can_access_lecture?` — single server-side authority.
- [x] `create_pending_enrollment/2` (status `pending → active`), unique
      `(user_id, course_id)`.
- [x] Enforce gate in every content/token path (course player, lecture, media
      token) — never trust the client.
- [x] Tests proving no content/token is served without an active enrollment.

## Phase 4 — Payments: Paystack 💳

- [x] Define a `Payments.Provider` behaviour (`initiate/verify`) so Paystack can
      be replaced with Mox in tests.
- [x] Adapt and harden the existing `Wasomi.Paystack` initialize/verify client:
      consistent return tuples, configurable API URL/callback URL, runtime
      secret only, and no hardcoded fallback key.
- [x] Create pending enrollment + payment before initialization; send Paystack
      the amount in minor units and use the payment's unique
      `provider_reference` as the transaction reference/idempotency key.
- [x] Store relevant Paystack responses/events in `raw_payload`; never store
      card details.
- [x] Add a **Checkout LiveView**: "Enroll & Pay" → initialize transaction →
      redirect to Paystack's hosted checkout → waiting/verification state.
- [x] Add a browser callback route that verifies the transaction server-side;
      never activate an enrollment from callback query parameters alone.
- [x] Add a signature-verified Paystack **webhook** controller
      (`x-paystack-signature`, HMAC-SHA512) that enqueues an idempotent Oban
      `ProcessPaystackWebhook` job and responds quickly.
- [x] Worker: verify the transaction with Paystack, atomically mark the payment
      successful, activate the enrollment, and broadcast
      `{:payment_confirmed, enrollment}` on `"user:{id}"`.
- [x] Checkout subscribes to PubSub and redirects to the course after the
      enrollment is activated. (design.md)
- [x] Add an Oban **cron reconciliation** job for `pending` payments older than
      ~2 minutes by querying Paystack's verify endpoint.
- [x] Tests with Mox: initialization, success, failure, invalid signature,
      verify-on-webhook, duplicate/replayed webhook, browser callback safety,
      and dropped webhook → reconciled.

## Phase 5 — Media (video delivery & protection) 🎬

- [x] `Media` behaviour + adapter (**Mux**).
- [x] `playback_token/3`: short-lived, viewer-bound — minted **only** after
      Enrollments gate passes (403 otherwise).
- [x] Admin direct-upload flow → store returned `video_asset_id`.
- [x] LiveView video player + JS hook (HLS / provider player).
- [x] Content-protection deterrents: no raw URLs, disable context menu, dynamic
      email watermark overlay (project.md §8).

## Phase 6 — Learning (progress & completion) 📈

- [x] `Learning` API: upsert progress (`user_id+lecture_id` unique),
      `last_position_seconds`, completion at ~95% or explicit "Mark complete".
- [x] JS hook pushes `timeupdate`/`ended` → save progress.
- [x] Completion roll-up: lecture → module → course; emit completion events.
- [x] Course player LiveView: live progress bar, "next lecture" unlock.
- [x] Tests for completion thresholds & module/course roll-up.

## Phase 7 — Certificates 🏅

- [ ] `Certificates` API: issue per **module** and per **course**; unique
      `serial_number`.
- [ ] Branded Heex template (logo, brand colors, name, title, date, serial).
- [ ] Oban `IssueCertificate` (unique per user+scope) → ChromicPDF render →
      upload to **R2** → create `certificates` row → notify learner.
- [ ] Signed short-lived R2 download URL; dashboard download button (PubSub
      "certificate ready").
- [ ] Tests: issuance triggered by completion, idempotency, no duplicate serial.

## Phase 8 — Notifications

- [ ] Swoosh mailers via Oban `mailers` queue: welcome, payment confirmed,
      certificate issued.
- [ ] Trigger from domain events; configure transactional provider (SES/Resend).

## Phase 9 — Learner dashboard

- [x] "My courses" / continue-watching LiveView.
- [x] Progress per course, certificate downloads, payment receipts.

## Phase 10 — Admin

- [ ] Role-gated admin section (repurpose generated CRUD LiveViews, add to
      router under admin pipeline).
- [ ] CRUD courses/modules/lectures + drag-and-drop reorder.
- [ ] Learner/enrollment management, payments/receipts, manual "verify/
      reconcile payment".
- [ ] Basic analytics (Ecto aggregates): registrations, payments (count/sum/
      success rate), completion rates.

## Phase 11 — Hardening, observability & deploy

- [ ] Rate-limiting on auth + payment-init endpoints; verify CSRF, secure
      headers, HSTS.
- [ ] LiveDashboard behind admin auth; Telemetry on payment lifecycle + cert
      issuance; Sentry/AppSignal.
- [ ] CI (GitHub Actions): `mix format --check` · `credo` · `mix test`.
- [ ] Fly.io deploy (region `jnb`), Dockerfile incl. Chrome for ChromicPDF,
      Postgres + backups, R2 bucket, custom domain + TLS.

---

## Open questions to resolve (from project.md §17)

- [ ] First course price + currency (assume KES, one-time)?
- [ ] Paystack: sandbox first or live credentials available?
- [x] Video provider decision: **Mux** for v1.
- [ ] Certificate design: Tailwind template OK or fixed design to match?
- [ ] Final brand assets (logo, exact hex) timeline.
</content>
</invoke>
