defmodule Wasomi.Certificates do
  @moduledoc """
  Issues and serves learner-owned course certificates.

  Scope uniqueness is enforced both by Oban and partial database indexes. A
  deterministic serial and object key make retries safe even if a worker dies
  after uploading but before inserting the database row.
  """

  import Ecto.Query, warn: false

  alias Wasomi.Accounts.User
  alias Wasomi.Catalog.Course
  alias Wasomi.Certificates.Certificate
  alias Wasomi.Certificates.Workers.IssueCertificate
  alias Wasomi.Learning
  alias Wasomi.Repo

  @download_ttl 300

  def list_certificates do
    Certificate
    |> order_by([certificate], desc: certificate.issued_at)
    |> Repo.all()
  end

  @doc """
  Counts course certificates issued, optionally scoped to a single course.
  Used by the admin conversion funnel as its terminal "Certified" step.
  """
  def count_course_certificates(opts \\ []) do
    course_id = Keyword.get(opts, :course_id)

    Certificate
    |> where([c], c.type == :course)
    |> filter_course(course_id)
    |> Repo.aggregate(:count)
  end

  defp filter_course(query, nil), do: query
  defp filter_course(query, course_id), do: where(query, [c], c.course_id == ^course_id)

  def list_for_user(%User{id: user_id}) do
    Certificate
    |> where([certificate], certificate.user_id == ^user_id)
    |> order_by([certificate], desc: certificate.issued_at)
    |> preload(:course)
    |> Repo.all()
  end

  def list_for_user_course(%User{id: user_id}, %Course{id: course_id}) do
    Certificate
    |> where(
      [certificate],
      certificate.user_id == ^user_id and certificate.course_id == ^course_id
    )
    |> order_by([certificate], asc: certificate.issued_at)
    |> preload(:course)
    |> Repo.all()
  end

  def get_certificate!(id), do: Repo.get!(Certificate, id)

  def get_user_certificate!(%User{id: user_id}, id) do
    Certificate
    |> where([certificate], certificate.id == ^id and certificate.user_id == ^user_id)
    |> Repo.one!()
  end

  def create_certificate(attrs \\ %{}) do
    %Certificate{}
    |> Certificate.changeset(attrs)
    |> Repo.insert()
  end

  def update_certificate(%Certificate{} = certificate, attrs) do
    certificate
    |> Certificate.changeset(attrs)
    |> Repo.update()
  end

  def delete_certificate(%Certificate{} = certificate), do: Repo.delete(certificate)

  def change_certificate(%Certificate{} = certificate, attrs \\ %{}) do
    Certificate.changeset(certificate, attrs)
  end

  @doc """
  Enqueues a certificate job for a newly completed course.
  """
  def enqueue_for_completion_events(%User{} = user, events) when is_list(events) do
    events
    |> Enum.flat_map(fn
      {:course_completed, %Course{id: course_id}} ->
        [IssueCertificate.for_course(user.id, course_id)]

      _ ->
        []
    end)
    |> Enum.map(&Oban.insert/1)
    |> then(fn results ->
      if Enum.all?(results, &match?({:ok, _}, &1)), do: :ok, else: {:error, results}
    end)
  end

  @doc """
  Performs one idempotent issuance after re-checking completion.
  """
  def issue(user_id, course_id) do
    with %User{} = user <- Repo.get(User, user_id),
         {:ok, course} <- load_completed_course(user, course_id) do
      case get_by_course(user.id, course.id) do
        %Certificate{} = certificate ->
          {:ok, preload_certificate(certificate), :existing}

        nil ->
          if course.certificate_enabled do
            issue_new(user, course)
          else
            {:error, :certificates_disabled}
          end
      end
    else
      nil -> {:error, :user_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def subscribe(%User{id: id}) do
    Phoenix.PubSub.subscribe(Wasomi.PubSub, user_topic(id))
  end

  def broadcast_ready(%Certificate{} = certificate) do
    Phoenix.PubSub.broadcast(
      Wasomi.PubSub,
      user_topic(certificate.user_id),
      {:certificate_ready, certificate}
    )
  end

  def download_url(%User{} = user, certificate_or_id, opts \\ []) do
    certificate =
      case certificate_or_id do
        %Certificate{} = certificate -> certificate
        id -> get_user_certificate!(user, id)
      end

    if certificate.user_id == user.id do
      storage().signed_url(
        certificate.file_key,
        Keyword.put_new(opts, :expires_in, @download_ttl)
      )
    else
      {:error, :forbidden}
    end
  end

  defp issue_new(user, course) do
    issued_at = DateTime.utc_now() |> DateTime.truncate(:second)
    serial_number = serial_number(user.id, course.id)
    file_key = file_key(user.id, course.id)

    assigns = %{
      learner_name: user.name,
      title: course.title,
      type_label: "Course Achievement",
      issued_on: Calendar.strftime(issued_at, "%B %-d, %Y"),
      serial_number: serial_number,
      issuer_name: course.certificate_issuer_name || "Wasomi Business Institute",
      signatory_name: course.certificate_signatory_name,
      signatory_title: course.certificate_signatory_title,
      signature_url: course.certificate_signature_key
    }

    with {:ok, pdf} <- renderer().render(assigns),
         :ok <- storage().upload(file_key, pdf),
         {:ok, certificate} <-
           create_certificate(%{
             type: :course,
             serial_number: serial_number,
             file_key: file_key,
             issued_at: issued_at,
             user_id: user.id,
             course_id: course.id
           }) do
      {:ok, preload_certificate(certificate), :created}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        case get_by_course(user.id, course.id) do
          %Certificate{} = certificate -> {:ok, preload_certificate(certificate), :existing}
          nil -> {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_completed_course(user, course_id) do
    case Repo.get(Course, course_id) do
      nil ->
        {:error, :scope_not_found}

      course ->
        if Learning.course_complete?(user, course), do: {:ok, course}, else: {:error, :incomplete}
    end
  end

  defp get_by_course(user_id, course_id) do
    Repo.get_by(Certificate, user_id: user_id, type: :course, course_id: course_id)
  end

  defp preload_certificate(certificate), do: Repo.preload(certificate, [:user, :course])

  defp serial_number(user_id, course_id) do
    digest =
      :crypto.hash(:sha256, "#{user_id}:course:#{course_id}")
      |> Base.encode16(case: :upper)
      |> binary_part(0, 12)

    "KBI-CRS-#{digest}"
  end

  defp file_key(user_id, course_id), do: "certificates/#{user_id}/course/#{course_id}.pdf"

  defp renderer, do: Application.fetch_env!(:wasomi, :certificate_renderer)
  defp storage, do: Application.fetch_env!(:wasomi, :certificate_storage)
  defp user_topic(user_id), do: "user:#{user_id}"
end
