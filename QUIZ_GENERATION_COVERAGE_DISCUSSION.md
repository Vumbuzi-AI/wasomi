# Quiz generation: document coverage — for team discussion

Status: discussion draft. Partially implemented (see "Already shipped"
below). The truncation-tracking piece described here was built, then
reverted pending this discussion — not currently in the codebase.

## The problem

AI quiz generation sends the extracted document text to the LLM in one
call. The adapter (`Wasomi.Assessments.QuestionGenerator.OpenAI`) truncates
source text to a character limit before it reaches the model
(`@max_source_chars`, `lib/wasomi/assessments/question_generator/open_ai.ex`).
Anything past that limit is invisible to the model — no prompt wording can
fix that, since the text was never sent.

Separately, even within whatever text *does* reach the model, coverage
(does every section/topic actually get a question) was previously
prompt-trust-only: we asked the model to "spread out" with no structure
behind that ask.

## Already shipped (this session)

- **Raised the limit**: 60,000 → 200,000 characters (~35-40k words).
  Tradeoffs documented inline at the constant: more chars = more input
  tokens billed + slower responses + "lost in the middle" (LLMs attend less
  reliably to content buried in the middle of a very long prompt, so raising
  the limit helps but doesn't guarantee the model actually uses all of it
  well). 200k is a judgment call, not a hard technical ceiling — it's a
  balance point, open to revisiting.
- **Structured coverage instruction**: the prompt now asks the model to
  first identify the document's distinct sections/topics, then allocate
  questions so every topic gets at least one question before any topic gets
  a second — replacing the old vague "spread out" ask with something the
  model can concretely act on. Same single API call, same cost, no new
  admin action.
- **Interim answer for documents that still exceed the limit**: nothing
  automatic. The admin's recourse is the manual "Add question" feature
  (already built) if they judge the generated set doesn't cover the
  document well enough. No warning, no auto-detection of truncation today.

## What's still open

### 1. Should truncation be flagged to the admin at all?

Two shapes this could take, both discussed and neither built:

- **Ephemeral (no schema change)**: worker broadcasts a one-off notice over
  PubSub when it truncates. Simple, zero persistence — but only reaches an
  admin who's actively watching the page when the job finishes. Since this
  whole feature exists so admins can upload and walk away, this could be
  silently missed the same way an earlier bug in this project let generated
  drafts go unnoticed until a page reload.
- **Persisted (schema change)**: a `source_truncated` boolean on
  `quiz_generations`, discoverable later in Generation History regardless
  of whether anyone was watching live. More durable, but it's a real schema
  change for what might be a rare case — reverted once already after being
  flagged as more machinery than the problem warranted.

Decision needed: is "discoverable after the fact" worth a schema change, or
is "visible only if watching live" (or nothing at all) good enough?

### 2. What should happen for documents that exceed even the raised limit?

Two fundamentally different approaches, not a spectrum:

- **Manual, incremental** ("process the next chunk"): admin explicitly
  triggers additional generation rounds over subsequent sections of the
  document when they want more coverage. Reuses the existing single-shot
  pipeline almost unchanged; each round becomes another Generation History
  entry (already supports per-batch discard, status, etc.). Real
  prerequisite: extracted document text isn't persisted anywhere today —
  it's pulled from the PDF, used once, and discarded. Chunked continuation
  needs it stored somewhere (or the admin re-uploads the same file each
  round, which is clunky and error-prone). Cost scales only with what the
  admin actually asks for.
- **Automatic, full chunking**: one "Generate questions" click triggers the
  worker to split the whole document into chunks and make multiple LLM
  calls internally, aggregating results into one batch. Zero extra admin
  steps — same one-click experience regardless of document length. Real
  cost: meaningfully bigger engineering lift (chunk-boundary strategy,
  multi-call orchestration inside one Oban job, failure handling when one
  chunk fails but others succeed, total job latency scaling with document
  length — a long document could take several minutes end-to-end, still
  async so it doesn't block the admin's UI, but a real change from today's
  single-call latency). Cost/latency scale with document length on *every*
  generation, whether or not that much coverage was actually wanted.

Current direction from this conversation: automatic full chunking is
preferred *if* we build this at all, for the "admin never has to think
about it" property — but it has not been scoped or built. This document
exists so the team can weigh in before any of it starts.

### 3. If we build #2 (automatic chunking), a semantics question follows

Today "Number of questions" is a total the admin requests, capped *down*
for thin content. With chunking, does that number:

- **Stay a total** — distributed across however many chunks the document
  needs (e.g. 20 requested → ~7/7/6 across 3 chunks). Matches today's
  mental model regardless of document length.
- **Become per-chunk** — scales *up* with document length (10 "per
  section" on a 3-chunk document → ~30 total). More coverage for longer
  material, but the field now means something length-dependent, which is a
  real change to what the admin should expect when they type a number.

This wasn't settled before the discussion got parked — worth deciding
alongside #2, not as an afterthought once chunking is half-built.

## Recommendation if the team wants a quick answer

Ship what's already in place (raised limit + structured prompt) and treat
it as good enough for now, since it requires zero further engineering.
Revisit chunking only if real usage shows admins regularly hitting the
200k-character ceiling with training documents that genuinely need full,
guaranteed coverage — building #2 speculatively, before that's confirmed to
be a real recurring problem, risks being the same kind of over-scoped
solution the truncation-flag work already got pulled back from once.
