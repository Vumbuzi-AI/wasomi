defmodule Wasomi.Notifications.Workers.SendGoneQuietReengagement do
  @moduledoc """
  Daily cron: nudges learners who made progress in a course, then stalled.
  One `%{"touch" => 1 | 2 | 3}` job per touch of the sequence, each on its
  own crontab entry — see `config/config.exs`.

  `Wasomi.Learning.list_gone_quiet_enrollments/1` only returns enrollments
  with at least one recorded lecture-progress row, which structurally
  excludes anyone `SendNeverStartedReengagement` would also target — the
  two workers can never both fire for the same learner.
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
  # list, but `deliver_reengagement_gone_quiet/2`'s reservation makes
  # already-sent ones a no-op, so nothing double-sends.
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    touch = Map.get(args, "touch", 1)

    errors =
      touch
      |> Learning.list_gone_quiet_enrollments()
      |> Enum.map(&Notifications.deliver_reengagement_gone_quiet(&1, touch))
      |> Enum.filter(&match?({:error, _reason}, &1))

    if errors == [], do: :ok, else: {:error, errors}
  end
end
