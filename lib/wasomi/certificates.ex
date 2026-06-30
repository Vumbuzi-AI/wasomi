defmodule Wasomi.Certificates do
  @moduledoc """
  Issues and serves learner-owned module and course certificates.

  Scope uniqueness is enforced both by Oban and partial database indexes. A
  deterministic serial and object key make retries safe even if a worker dies
  after uploading but before inserting the database row.
  """

  import Ecto.Query, warn: false

  alias Wasomi.Accounts.User
  alias Wasomi.Catalog.{Course, CourseModule}
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

  def list_for_user(%User{id: user_id}) do
    Certificate
    |> where([certificate], certificate.user_id == ^user_id)
    |> order_by([certificate], desc: certificate.issued_at)
    |> preload([:course, :module])
    |> Repo.all()
  end

  def list_for_user_course(%User{id: user_id}, %Course{id: course_id}) do
    Certificate
    |> where(
      [certificate],
      certificate.user_id == ^user_id and certificate.course_id == ^course_id
    )
    |> order_by([certificate], asc: certificate.type, asc: certificate.issued_at)
    |> preload([:course, :module])
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
  Enqueues certificate jobs for newly completed module/course transitions.
  """
  def enqueue_for_completion_events(%User{} = user, events) when is_list(events) do
    events
    |> Enum.flat_map(fn
      {:module_completed, %CourseModule{id: scope_id}} ->
        [IssueCertificate.new(user.id, :module, scope_id)]

      {:course_completed, %Course{id: scope_id}} ->
        [IssueCertificate.new(user.id, :course, scope_id)]

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
  def issue(user_id, type, scope_id) when type in [:module, :course] do
    with %User{} = user <- Repo.get(User, user_id),
         {:ok, scope} <- load_completed_scope(user, type, scope_id) do
      case get_by_scope(user.id, type, scope_id) do
        %Certificate{} = certificate ->
          {:ok, preload_certificate(certificate), :existing}

        nil ->
          issue_new(user, type, scope)
      end
    else
      nil -> {:error, :user_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def issue(_user_id, _type, _scope_id), do: {:error, :invalid_scope}

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

  defp issue_new(user, type, scope) do
    issued_at = DateTime.utc_now() |> DateTime.truncate(:second)
    scope_id = scope_id(type, scope)
    serial_number = serial_number(user.id, type, scope_id)
    file_key = file_key(user.id, type, scope_id)
    course = course_for(type, scope)

    assigns = %{
      learner_name: user.name,
      title: scope.title,
      type_label: if(type == :module, do: "Module Achievement", else: "Course Achievement"),
      issued_on: Calendar.strftime(issued_at, "%B %-d, %Y"),
      serial_number: serial_number
    }

    with {:ok, pdf} <- renderer().render(assigns),
         :ok <- storage().upload(file_key, pdf),
         {:ok, certificate} <-
           create_certificate(%{
             type: type,
             serial_number: serial_number,
             file_key: file_key,
             issued_at: issued_at,
             user_id: user.id,
             course_id: course.id,
             module_id: if(type == :module, do: scope.id)
           }) do
      {:ok, preload_certificate(certificate), :created}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        case get_by_scope(user.id, type, scope_id) do
          %Certificate{} = certificate -> {:ok, preload_certificate(certificate), :existing}
          nil -> {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_completed_scope(user, :module, module_id) do
    case Repo.get(CourseModule, module_id) |> Repo.preload(:course) do
      nil ->
        {:error, :scope_not_found}

      module ->
        if Learning.module_complete?(user, module), do: {:ok, module}, else: {:error, :incomplete}
    end
  end

  defp load_completed_scope(user, :course, course_id) do
    case Repo.get(Course, course_id) do
      nil ->
        {:error, :scope_not_found}

      course ->
        if Learning.course_complete?(user, course), do: {:ok, course}, else: {:error, :incomplete}
    end
  end

  defp get_by_scope(user_id, :module, module_id) do
    Repo.get_by(Certificate, user_id: user_id, type: :module, module_id: module_id)
  end

  defp get_by_scope(user_id, :course, course_id) do
    Repo.get_by(Certificate, user_id: user_id, type: :course, course_id: course_id)
  end

  defp preload_certificate(certificate), do: Repo.preload(certificate, [:user, :course, :module])
  defp course_for(:module, module), do: module.course
  defp course_for(:course, course), do: course
  defp scope_id(:module, module), do: module.id
  defp scope_id(:course, course), do: course.id

  defp serial_number(user_id, type, scope_id) do
    digest =
      :crypto.hash(:sha256, "#{user_id}:#{type}:#{scope_id}")
      |> Base.encode16(case: :upper)
      |> binary_part(0, 12)

    prefix = if type == :module, do: "MOD", else: "CRS"
    "KBI-#{prefix}-#{digest}"
  end

  defp file_key(user_id, type, scope_id),
    do: "certificates/#{user_id}/#{type}/#{scope_id}.pdf"

  defp renderer, do: Application.fetch_env!(:wasomi, :certificate_renderer)
  defp storage, do: Application.fetch_env!(:wasomi, :certificate_storage)
  defp user_topic(user_id), do: "user:#{user_id}"
end
