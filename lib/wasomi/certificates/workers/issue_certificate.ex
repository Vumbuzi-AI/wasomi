defmodule Wasomi.Certificates.Workers.IssueCertificate do
  @moduledoc """
  Renders, stores, persists, and announces a certificate exactly once per
  course completion.
  """

  use Oban.Worker,
    queue: :certificates,
    max_attempts: 8,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:user_id, :course_id],
      # Only a live job blocks a fresh insert, so `ensure_issued/2` and the
      # sweep can recover a terminal one. `issue/2`'s `get_by_course` check
      # still prevents a double-issue.
      states: [:available, :scheduled, :executing, :retryable, :suspended]
    ]

  require Logger

  alias Wasomi.Certificates
  alias Wasomi.Notifications.Workers.DeliverCertificateIssued

  # Deliberately not named `new/2` — Oban.Worker's `use` already defines
  # `new/1,2` (via a default `opts \\ []` arg), and `defoverridable`
  # silently lets a same-arity redefinition here fully *replace* that
  # implementation rather than add a pattern-matched clause alongside it.
  # A `new(user_id, course_id)` wrapper under that name previously called
  # back into itself through Oban's own arity-1 delegate, doubling its
  # argument on every recursive step until the process ran out of memory.
  def for_completion(user_id, course_id) do
    __MODULE__.new(%{user_id: user_id, course_id: course_id})
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "course_id" => course_id}} = job) do
    case Certificates.issue(user_id, course_id) do
      {:ok, certificate, :created} ->
        :ok = Certificates.broadcast_ready(certificate)
        {:ok, _job} = Oban.insert(DeliverCertificateIssued.for_certificate(certificate.id))
        :ok

      {:ok, _certificate, :existing} ->
        :ok

      {:error, reason} ->
        # Transient errors retry; the rest cancel (no 8-retry burn) and the
        # sweep re-enqueues once the cause is fixed.
        case Certificates.classify_error(reason) do
          :retry ->
            {:error, reason}

          :cancel ->
            Logger.error(
              "IssueCertificate cancelled for user=#{user_id} course=#{course_id} " <>
                "attempt=#{job.attempt}: #{inspect(reason)}"
            )

            {:cancel, reason}
        end
    end
  end
end
