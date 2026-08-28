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
      states: :all
    ]

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
  def perform(%Oban.Job{args: %{"user_id" => user_id, "course_id" => course_id}}) do
    case Certificates.issue(user_id, course_id) do
      {:ok, certificate, :created} ->
        :ok = Certificates.broadcast_ready(certificate)
        {:ok, _job} = Oban.insert(DeliverCertificateIssued.for_certificate(certificate.id))
        :ok

      {:ok, _certificate, :existing} ->
        :ok

      # Not transient — retrying can never issue a certificate for a course
      # the admin has turned off, so treat it as a deliberate no-op instead
      # of burning all 8 retry attempts and surfacing as a job failure.
      # Note this job's `unique` config (period: :infinity, states: :all)
      # still blocks a fresh insert for this scope even after completing
      # here — if the admin re-enables certificates later, nothing
      # re-triggers issuance for a learner who completed while disabled.
      {:error, :certificates_disabled} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
