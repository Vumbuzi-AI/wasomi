# Group 4 — Admin-customizable landing images

Branch: `kendi/landing-page-image-slots` (off `main`, uncommitted — left for
human review per instructions).

## Enumerated slot list

Every hardcoded `/images/...` `src=` found in
`lib/wasomi_web/components/home_components.ex`:

| Line | Function          | File                          | Included as a slot? |
|------|-------------------|--------------------------------|----------------------|
| 57   | `home_header`     | `/images/logo.png`             | No — brand mark |
| 255  | `hero`            | `/images/hero-home.png`        | **Yes** — `hero` |
| 325  | `about_wasomi`    | `/images/gs1-box.png`          | No — see below |
| 402  | `gs1_in_action` (step 1 visual) | `/images/gs1-box.png`   | **Yes** — `gs1_step_identify` |
| 414  | `gs1_in_action` (step 2 visual) | `/images/hero-home.png` | **Yes** — `gs1_step_capture` |
| 428  | `gs1_in_action` (step 3 visual) | `/images/hero_image.jpg`| **Yes** — `gs1_step_share` |
| 442  | `gs1_in_action` (step 4 visual) | `/images/auth-learning-bg.jpg` | **Yes** — `gs1_step_verify` |
| 903  | decorative mock certificate card | `/images/logo.png`   | No — brand mark |
| 1221 | `footer`          | `/images/logo-reversed.png`    | No — brand mark |

**Final slot set (5):** `hero`, `gs1_step_identify`, `gs1_step_capture`,
`gs1_step_share`, `gs1_step_verify`.

**Excluded, and why:**
- `logo.png` / `logo-reversed.png` (3 occurrences) — the Wasomi brand mark,
  reused as site chrome (nav, footer, a decorative mock-UI card), not unique
  marketing content. `TODO.md`'s own decision note scopes this feature
  explicitly to "hero, GS1 step visuals" — brand identity swapping is a
  materially different, riskier feature (it'd also need to stay consistent
  with the logo used on `core_components.ex`'s auth pages, outside this
  component file entirely) and isn't asked for here.
- The `about_wasomi` section's GS1 box image (line 325) — this is the
  "About Wasomi" illustration, not a hero or step visual. It happens to
  reuse the same default file as the step-1 visual, but it's a separate
  section with its own composition (rotated card, decorative pins). Left
  out to stay inside the explicit "hero, GS1 step visuals" scope from
  `TODO.md`'s decisions section, rather than quietly expanding it. If this
  turns out to be wanted, adding it is a one-line addition to
  `LandingImage.slots/0` / `@defaults` / `@labels` and one wire-in edit —
  the schema and admin UI don't need to change shape at all.

## File-size limit

Certificate signatures reuse: transparent PNG, 2 MB (`Wasomi.Storage.R2`'s
`@max_image_bytes`, enforced both in the LiveView's `allow_upload` and
again server-side in the adapter).

Landing images are full-bleed marketing photography (a homepage hero
banner, four "See GS1 in action" step visuals), not a small signature
graphic — 2 MB is easy to blow past for those at real quality. Chosen limit:
**5 MB**, format restricted to PNG (same convention as certificates).
5 MB comfortably fits a high-quality hero-sized PNG while staying well
under a hard 10 MB ceiling I added in `Wasomi.Storage.R2` for any
caller-supplied override (see below) — a safety net against a future
caller passing an unreasonable limit, not something this feature needs to
hit.

`Wasomi.Storage.R2.presign_upload/2` previously hardcoded one 2 MB ceiling
for every `image/png` upload regardless of caller. Rather than raising that
global constant (which would have silently loosened the certificate-
signature limit too), I threaded through an optional `"max_image_bytes"`
attr that a caller can set to raise its own ceiling, clamped to a new
`@max_image_bytes_ceiling` (10 MB) regardless of what's requested. The
certificate flow doesn't pass this attr, so its behavior (and its test
`R2 rejects unsupported or oversized upload metadata`) is byte-for-byte
unchanged. `WasomiWeb.AdminLive.LandingImages` is the only caller that
passes `"max_image_bytes" => 5_000_000`.

## Caching decision

`Wasomi.Content.landing_image_map/0` does **one** `SELECT slot, image_url
FROM landing_images` (at most 5 rows, unique-indexed on `slot`) per landing
page render, called once in `HomeLive.mount/3` and threaded down to `hero/1`
and `gs1_in_action/1` as an `images` assign — not five separate
`image_url_for/1` queries, one per `<img>`.

Explicit decision: **no additional cache layer** (ETS/Cachex/
`:persistent_term`) for this. The table is tiny (bounded at 5 rows forever,
since slots are a fixed compile-time set) and the query is a single indexed
lookup with no joins — this is already about as cheap as a DB round trip
gets, and Ecto/Postgrex connection pooling means it's not adding a new
class of cost to the page. Adding a cache here now would be optimizing
before there's evidence it's needed, and would add invalidation complexity
(bust on `put_landing_image/2` and `reset_landing_image/1`) for a query
that isn't the bottleneck. If landing-page traffic or DB load ever makes
this worth revisiting, `Content.landing_image_map/0` is the single seam to
add caching behind — no caller changes needed.

## Files touched

**New:**
- `lib/wasomi/content.ex` — new `Wasomi.Content` context
- `lib/wasomi/content/landing_image.ex` — `LandingImage` schema, slot/label/default registry
- `priv/repo/migrations/20260827040000_create_landing_images.exs`
- `lib/wasomi_web/live/admin_live/landing_images.ex` — admin slot list/upload/reset page
- `test/wasomi/content_test.exs`
- `test/wasomi_web/live/admin_live/landing_images_test.exs`
- `test/support/fixtures/content_fixtures.ex`

**Edited:**
- `lib/wasomi/storage/r2.ex` — optional `max_image_bytes` override, clamped to a new 10 MB ceiling
- `lib/wasomi_web/router.ex` — `/admin/landing-images` route
- `lib/wasomi_web/components/admin_components.ex` — new sidebar nav item
- `lib/wasomi_web/components/home_components.ex` — `hero/1` and `gs1_in_action/1` now take an `images` assign instead of hardcoding paths
- `lib/wasomi_web/live/home_live.ex` — resolves `Content.landing_image_map/0` once, passes it down
- `test/wasomi/storage_test.exs` — tests for the `max_image_bytes` override and its ceiling

## Test results

- `mix format` — clean on every touched file, no changes needed on final pass.
- `mix credo --strict` — clean on every touched file (0 issues).
- `mix test` (full suite): **959 tests, 14 failures** — all 14 pre-existing
  and unrelated to this change (`CoursePlayerLiveTest` ×4,
  `StudyHubLiveTest` ×5, `AdminLiveTest` ×2, `AssessmentsTest` ×1,
  `LectureLive.FormComponentTest` ×2 — matches the task's stated known-
  failure set). Zero failures in any new or touched file for this feature.
- New/changed test coverage:
  - `Wasomi.ContentTest` — `landing_image_map/0` (all-default and
    mixed-override cases), `image_url_for/1` (default, override, invalid
    slot raises), `list_landing_image_slots/0` (shape, override flag),
    `put_landing_image/2` (create, replace-not-duplicate via upsert,
    invalid slot rejected, blank `image_url` rejected), `reset_landing_image/1`
    (clears an override, no-op when none exists).
  - `WasomiWeb.AdminLive.LandingImagesTest` — renders every slot with
    label/default, shows an overridden slot's custom image, authorization
    boundary (learner and anonymous visitor both redirected away),
    upload → save persists the override end to end, reset clears an
    override back to default, missing-`R2_PUBLIC_URL` flashes an error
    instead of silently dropping the upload (mirrors the equivalent
    certificate-flow test).
  - `Wasomi.StorageTest` additions — a caller-supplied `max_image_bytes`
    is honored (rejects between the default 2 MB and the requested
    ceiling), and is itself clamped to the 10 MB hard ceiling regardless
    of what's requested.

## Manual testing steps

1. `mix ecto.migrate` (dev), then `mix phx.server`.
2. Visit `/` — confirm the hero banner and all four "See GS1 in action"
   step images render exactly as before (no admin overrides exist yet).
3. Log in as an admin, visit `/admin/landing-images` — confirm the sidebar
   has a "Landing page" entry, and the page lists all 5 slots, each showing
   its current (default) image.
4. Pick a PNG under 5 MB for the "Hero banner" slot — confirm a live
   preview appears before saving, click "Save" — confirm a flash confirms
   the update and the card now says "Custom image".
5. Reload `/` — confirm the hero banner now shows the uploaded image.
6. Back in `/admin/landing-images`, click "Reset to default" on that slot —
   confirm it flashes a confirmation, the card reverts to "Default image",
   and `/` reflects the original hero image again.
7. Try uploading a non-PNG (e.g. a `.jpg`) or a file over 5 MB — confirm a
   clear inline error, nothing saved.
8. Repeat steps 4–6 for one of the four GS1 step slots — confirm only that
   step's visual changes on `/`, the other three are unaffected.
9. As a logged-in learner (non-admin) and as a logged-out visitor, try
   navigating directly to `/admin/landing-images` — confirm both are
   redirected away, never reaching the page.

## Self-review

- **Naming**: `LandingImage.image_url` stores a full URL (the R2
  `public_url`), same as `Course.certificate_signature_key` does today
  despite its `_key` suffix. I named the new field `image_url` rather than
  copying that `_key` naming, since it's more honest about what's actually
  stored — but it does mean the two nearest-neighbor upload flows in the
  codebase now use different naming conventions for the same kind of
  value. If this bothers a reviewer, the cert side is the one that could 
  stand renaming, not this one — not appropriate to change unprompted here.
- **Duplication**: `landing_image_map/0` and `list_landing_image_slots/0`
  both fetch overrides with the same `select({li.slot, li.image_url})`
  query. I left them as two separate small functions rather than forcing a
  shared abstraction, because they serve genuinely different callers
  (public page render vs. admin listing with extra fields) and the
  duplication is two lines of an `Ecto.Query`, not logic — collapsing them
  into one parameterized function would add a branch/flag for a marginal
  DRY win. Worth revisiting only if a third caller shows up.
- **`image_url_for/1`'s guard**: `Ecto.Enum`-backed atoms can't be listed
  in a function guard without duplicating the slot list as a literal, so I
  used `true = slot in LandingImage.slots()` as a runtime assertion instead
  of a guard clause. This is a slightly unusual pattern for this codebase
  (most guards here are compile-time literals) — flagging it explicitly in
  case a reviewer prefers `slots()` to raise its own descriptive error
  instead of `MatchError`.
- **Upload UI reuse**: `LandingImages`'s `slot_card/1` duplicates a fair
  amount of markup from `CourseCertificate`'s `signature_upload/1` (entry
  list, progress bar, error rendering). I didn't extract a shared component
  because the two have different affordances (per-slot save+reset vs.
  one shared form, "Remove saved value" vs. "Reset to default" semantics
  are not quite the same action), but if a third upload-with-preview
  surface shows up, this is the point to extract a genuinely shared
  `WasomiWeb.CoreComponents` upload-with-preview component instead of a
  third copy.
- **Testing gap**: I did not add a test asserting the exact SQL query count
  for `landing_image_map/0` (e.g. via `Ecto.Adapters.SQL.Sandbox` query
  logging) to pin down "exactly one query" as a regression guard — I
  verified it by reading the implementation instead. Worth adding if this
  becomes a page where query-count regressions are a recurring risk.
- **Reused pattern, not partially cloned**: I read `CourseCertificate`
  closely before writing `LandingImages` and matched its
  presign/consume/error-string shape, its "flash a clear error rather than
  silently drop the upload when `R2_PUBLIC_URL` is unset" behavior, and its
  test structure (including the two inline `Storage`-mock modules), so this
  new admin surface should feel unsurprising to anyone who's touched the
  certificate flow.
