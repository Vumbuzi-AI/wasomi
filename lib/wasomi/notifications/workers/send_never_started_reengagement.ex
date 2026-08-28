defmodule Wasomi.Notifications.Workers.SendNeverStartedReengagement do
  @moduledoc """
  Daily cron: nudges learners who enrolled but never started a lecture.
  One `%{"touch" => 1 | 2 | 3}` job per touch of the sequence, each on its
  own crontab entry — see `config/config.exs`.

  Per-enrollment idempotency (never emailing the same learner twice for the
  same course+touch) is enforced by `Wasomi.Notifications.deliver_reengagement_never_started/2`
  itself, via a DB unique index — this worker's own `unique` config only
  prevents two cron ticks *of the same touch* from running the scan
  concurrently (`:args` is part of the uniqueness key, so touches 1/2/3
  don't block each other).
  """

  use Oban.Worker,
    queue: :mailers,
    max_attempts: 5,
    unique: [period: 82_800, fields: [:worker, :args]]

  alias Wasomi.Learning
  alias Wasomi.Notifications

  # One learner's delivery failing (a bad address, a transient mailer
  # error) must not block the nudge for everyone else in the batch — each
  # enrollment gets its own attempt, and the job only reports (and lets
  # Oban retry) the ones that actually failed. A retry re-scans the full
  # list, but `deliver_reengagement_never_started/2`'s unique index makes
  # already-sent ones a no-op, so nothing double-sends.
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    touch = Map.get(args, "touch", 1)

    errors =
      touch
      |> Learning.list_never_started_enrollments()
      |> Enum.map(&Notifications.deliver_reengagement_never_started(&1, touch))
      |> Enum.filter(&match?({:error, _reason}, &1))

    if errors == [], do: :ok, else: {:error, errors}
  end
end
