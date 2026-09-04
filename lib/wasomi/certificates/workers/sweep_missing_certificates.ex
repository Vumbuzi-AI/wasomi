defmodule Wasomi.Certificates.Workers.SweepMissingCertificates do
  @moduledoc """
  Safety net for the inline enqueue at course completion: periodically
  `ensure_issued/2`s every completed, certificate-enabled course still
  missing its certificate (`@batch` per run).
  """

  use Oban.Worker, queue: :certificates, max_attempts: 3

  require Logger

  import Ecto.Query

  alias Wasomi.Catalog.Course
  alias Wasomi.Certificates
  alias Wasomi.Certificates.Certificate
  alias Wasomi.Enrollments.Enrollment
  alias Wasomi.Repo

  @batch 50

  @impl Oban.Worker
  def perform(_job) do
    candidates()
    |> Enum.each(fn %{user_id: user_id, course_id: course_id} ->
      case Certificates.ensure_issued(user_id, course_id) do
        {:ok, _certificate} ->
          :ok

        :enqueued ->
          Logger.info("SweepMissingCertificates re-enqueued user=#{user_id} course=#{course_id}")

        {:error, reason} ->
          Logger.warning(
            "SweepMissingCertificates skip user=#{user_id} course=#{course_id}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end

  # `ensure_issued/2` does the per-course completion check, keeping this a
  # single cheap query.
  defp candidates do
    from(e in Enrollment,
      join: c in Course,
      on: c.id == e.course_id,
      left_join: cert in Certificate,
      on: cert.user_id == e.user_id and cert.course_id == e.course_id,
      where: e.status == :active and c.certificate_enabled and is_nil(cert.id),
      select: %{user_id: e.user_id, course_id: e.course_id},
      limit: @batch
    )
    |> Repo.all()
  end
end
