defmodule Wasomi.Enrollments do
  @moduledoc """
  The Enrollments context.
  """

  import Ecto.Query, warn: false
  alias Wasomi.Repo

  alias Wasomi.Accounts.User
  alias Wasomi.Catalog
  alias Wasomi.Catalog.{Course, Lecture}
  alias Wasomi.Enrollments.Enrollment

  @doc """
  Returns the list of enrollments.

  ## Examples

      iex> list_enrollments()
      [%Enrollment{}, ...]

  """
  def list_enrollments do
    Repo.all(Enrollment)
  end

  @doc """
  Lists a learner's active enrollments with the ordered course outline needed
  by learner-facing surfaces.

  Pending enrollments are intentionally excluded: they represent checkout
  attempts, not courses the learner may access.
  """
  def list_active_for_user(%User{id: user_id}) do
    Enrollment
    |> where([enrollment], enrollment.user_id == ^user_id and enrollment.status == :active)
    |> order_by([enrollment], desc: enrollment.activated_at, desc: enrollment.id)
    |> preload(course: [modules: :lectures])
    |> Repo.all()
  end

  @doc """
  Counts active enrollments across all courses.
  """
  def count_active do
    Enrollment
    |> where([e], e.status == :active)
    |> Repo.aggregate(:count)
  end

  @doc """
  Counts active enrollments keyed by `course_id`.
  """
  def count_active_by_course do
    Enrollment
    |> where([e], e.status == :active)
    |> group_by([e], e.course_id)
    |> select([e], {e.course_id, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Counts active enrollments keyed by `user_id`.
  """
  def count_active_by_user do
    Enrollment
    |> where([e], e.status == :active)
    |> group_by([e], e.user_id)
    |> select([e], {e.user_id, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Counts active enrollments for a single course.
  """
  def count_active_for_course(course_id) do
    Enrollment
    |> where([e], e.status == :active and e.course_id == ^course_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Lists active enrollments for a course with the learner preloaded, newest
  first. Used by the admin course detail page.
  """
  def list_active_for_course(course_id) do
    Enrollment
    |> where([e], e.status == :active and e.course_id == ^course_id)
    |> order_by([e], desc: e.activated_at, desc: e.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Gets a single enrollment.

  Raises `Ecto.NoResultsError` if the Enrollment does not exist.

  ## Examples

      iex> get_enrollment!(123)
      %Enrollment{}

      iex> get_enrollment!(456)
      ** (Ecto.NoResultsError)

  """
  def get_enrollment!(id), do: Repo.get!(Enrollment, id)

  def get_enrollment(user_or_id, course_or_id) do
    Repo.get_by(Enrollment,
      user_id: id_for(user_or_id),
      course_id: id_for(course_or_id)
    )
  end

  def enrolled?(user_or_id, course_or_id) do
    not is_nil(get_enrollment(user_or_id, course_or_id))
  end

  def active_enrollment(user_or_id, course_or_id) do
    Repo.get_by(Enrollment,
      user_id: id_for(user_or_id),
      course_id: id_for(course_or_id),
      status: :active
    )
  end

  def can_access_course?(nil, _course), do: false

  def can_access_course?(user_or_id, course_or_id) do
    not is_nil(active_enrollment(user_or_id, course_or_id))
  end

  def can_access_lecture?(nil, _lecture), do: false

  def can_access_lecture?(user_or_id, %Lecture{} = lecture) do
    course_id =
      from(module in Wasomi.Catalog.CourseModule,
        where: module.id == ^lecture.module_id,
        select: module.course_id
      )
      |> Repo.one()

    can_access_course?(user_or_id, course_id)
  end

  def can_access_lecture?(user_or_id, lecture_id) do
    lecture_id
    |> Catalog.get_lecture!()
    |> then(&can_access_lecture?(user_or_id, &1))
  end

  def authorize_course(user, course) do
    if can_access_course?(user, course), do: {:ok, course}, else: {:error, :forbidden}
  end

  def authorize_lecture(user, lecture_or_id) do
    lecture =
      case lecture_or_id do
        %Lecture{} = lecture -> lecture
        id -> Catalog.get_lecture!(id)
      end

    if can_access_lecture?(user, lecture), do: {:ok, lecture}, else: {:error, :forbidden}
  end

  def create_pending_enrollment(%User{id: user_id}, %Course{id: course_id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Enrollment{}
    |> Enrollment.changeset(%{
      user_id: user_id,
      course_id: course_id,
      status: :pending,
      enrolled_at: now
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:user_id, :course_id]
    )
    |> case do
      {:ok, %Enrollment{id: nil}} -> {:ok, get_enrollment(user_id, course_id)}
      result -> result
    end
  end

  def activate_enrollment(%Enrollment{status: :active} = enrollment), do: {:ok, enrollment}

  def activate_enrollment(%Enrollment{} = enrollment) do
    update_enrollment(enrollment, %{
      status: :active,
      activated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  @doc """
  Creates a enrollment.

  ## Examples

      iex> create_enrollment(%{field: value})
      {:ok, %Enrollment{}}

      iex> create_enrollment(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_enrollment(attrs \\ %{}) do
    %Enrollment{}
    |> Enrollment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a enrollment.

  ## Examples

      iex> update_enrollment(enrollment, %{field: new_value})
      {:ok, %Enrollment{}}

      iex> update_enrollment(enrollment, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_enrollment(%Enrollment{} = enrollment, attrs) do
    enrollment
    |> Enrollment.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a enrollment.

  ## Examples

      iex> delete_enrollment(enrollment)
      {:ok, %Enrollment{}}

      iex> delete_enrollment(enrollment)
      {:error, %Ecto.Changeset{}}

  """
  def delete_enrollment(%Enrollment{} = enrollment) do
    Repo.delete(enrollment)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking enrollment changes.

  ## Examples

      iex> change_enrollment(enrollment)
      %Ecto.Changeset{data: %Enrollment{}}

  """
  def change_enrollment(%Enrollment{} = enrollment, attrs \\ %{}) do
    Enrollment.changeset(enrollment, attrs)
  end

  defp id_for(%{id: id}), do: id
  defp id_for(id), do: id
end
