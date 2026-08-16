defmodule Wasomi.Certificates.Workers.IssueCertificate do
  @moduledoc """
  Renders, stores, persists, and announces a certificate once per course.
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

  def for_course(user_id, course_id) do
    __MODULE__.new(%{
      user_id: user_id,
      course_id: course_id
    })
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "course_id" => course_id}}) do
    case Certificates.issue(user_id, course_id) do
      {:ok, certificate, status} ->
        if status == :created do
          :ok = Certificates.broadcast_ready(certificate)
          {:ok, _job} = Oban.insert(DeliverCertificateIssued.for_certificate(certificate.id))
        end

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

  # Jobs enqueued before certificates became course-only must never issue a
  # retired module certificate. Treat them as deliberate no-ops.
  def perform(%Oban.Job{args: %{"type" => "module"}}), do: :ok

  def perform(%Oban.Job{
        args: %{"type" => "course", "user_id" => user_id, "scope_id" => course_id}
      }),
      do: perform(%Oban.Job{args: %{"user_id" => user_id, "course_id" => course_id}})

  def perform(%Oban.Job{}), do: {:discard, :invalid_scope}
end
