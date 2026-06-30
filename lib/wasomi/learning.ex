defmodule Wasomi.Learning do
  @moduledoc """
  Tracks lecture playback and derives module/course completion.

  Progress is monotonic: stale browser events cannot move a learner backwards,
  and a completed lecture cannot be reopened by a later `timeupdate`.
  """

  import Ecto.Query, warn: false
  alias Wasomi.Repo

  alias Wasomi.Accounts.User
  alias Wasomi.Catalog.{Course, CourseModule, Lecture}
  alias Wasomi.Certificates
  alias Wasomi.Enrollments
  alias Wasomi.Learning.LectureProgress

  @completion_ratio 0.95

  @doc """
  Saves a playback position and automatically completes the lecture at 95%.

  The persisted position is clamped to the lecture duration. Only active
  learners may record progress.
  """
  def record_progress(%User{} = user, %Lecture{} = lecture, position_seconds)
      when is_number(position_seconds) do
    persist_progress(user, lecture, position_seconds, false)
  end

  def record_progress(%User{}, %Lecture{}, _position_seconds),
    do: {:error, :invalid_position}

  @doc """
  Explicitly completes a lecture, used by the player `ended` event and the
  learner-facing "Mark complete" action.
  """
  def mark_complete(%User{} = user, %Lecture{} = lecture) do
    persist_progress(user, lecture, lecture.duration_seconds, true)
  end

  @doc """
  Returns one learner's progress row for a lecture, if it exists.
  """
  def get_lecture_progress(user_or_id, lecture_or_id) do
    Repo.get_by(LectureProgress,
      user_id: id_for(user_or_id),
      lecture_id: id_for(lecture_or_id)
    )
  end

  @doc """
  Returns a map keyed by lecture id for the requested course.
  """
  def progress_for_course(user_or_id, %Course{id: course_id}) do
    LectureProgress
    |> join(:inner, [progress], lecture in Lecture, on: lecture.id == progress.lecture_id)
    |> join(:inner, [_progress, lecture], module in CourseModule,
      on: module.id == lecture.module_id
    )
    |> where(
      [progress, _lecture, module],
      progress.user_id == ^id_for(user_or_id) and module.course_id == ^course_id
    )
    |> Repo.all()
    |> Map.new(&{&1.lecture_id, &1})
  end

  @doc """
  Produces course totals for the player and learner dashboard.
  """
  def course_progress(user_or_id, %Course{} = course) do
    lectures = course_lectures(course)
    progress = progress_for_course(user_or_id, course)
    completed = Enum.count(lectures, &(progress_status(progress, &1.id) == :completed))
    total = length(lectures)

    %{
      completed: completed,
      total: total,
      percent: percentage(completed, total),
      complete?: total > 0 and completed == total,
      progress: progress
    }
  end

  @doc """
  A lecture is unlocked when it is first in the course or every preceding
  lecture is completed.
  """
  def lecture_unlocked?(user_or_id, %Course{} = course, %Lecture{id: lecture_id}) do
    progress = progress_for_course(user_or_id, course)
    lectures = course_lectures(course)
    preceding = Enum.take_while(lectures, &(&1.id != lecture_id))

    length(preceding) < length(lectures) and
      Enum.all?(preceding, &(progress_status(progress, &1.id) == :completed))
  end

  @doc """
  Picks the first incomplete unlocked lecture, or the final lecture when the
  course is complete.
  """
  def next_lecture(user_or_id, %Course{} = course) do
    lectures = course_lectures(course)
    progress = progress_for_course(user_or_id, course)

    Enum.find(lectures, &(progress_status(progress, &1.id) != :completed)) ||
      List.last(lectures)
  end

  def subscribe(%User{id: id}) do
    Phoenix.PubSub.subscribe(Wasomi.PubSub, learning_topic(id))
  end

  @doc """
  Returns the list of lecture_progress.

  ## Examples

      iex> list_lecture_progress()
      [%LectureProgress{}, ...]

  """
  def list_lecture_progress do
    Repo.all(LectureProgress)
  end

  @doc """
  Gets a single lecture_progress.

  Raises `Ecto.NoResultsError` if the Lecture progress does not exist.

  ## Examples

      iex> get_lecture_progress!(123)
      %LectureProgress{}

      iex> get_lecture_progress!(456)
      ** (Ecto.NoResultsError)

  """
  def get_lecture_progress!(id), do: Repo.get!(LectureProgress, id)

  @doc """
  Creates a lecture_progress.

  ## Examples

      iex> create_lecture_progress(%{field: value})
      {:ok, %LectureProgress{}}

      iex> create_lecture_progress(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_lecture_progress(attrs \\ %{}) do
    %LectureProgress{}
    |> LectureProgress.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a lecture_progress.

  ## Examples

      iex> update_lecture_progress(lecture_progress, %{field: new_value})
      {:ok, %LectureProgress{}}

      iex> update_lecture_progress(lecture_progress, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_lecture_progress(%LectureProgress{} = lecture_progress, attrs) do
    lecture_progress
    |> LectureProgress.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a lecture_progress.

  ## Examples

      iex> delete_lecture_progress(lecture_progress)
      {:ok, %LectureProgress{}}

      iex> delete_lecture_progress(lecture_progress)
      {:error, %Ecto.Changeset{}}

  """
  def delete_lecture_progress(%LectureProgress{} = lecture_progress) do
    Repo.delete(lecture_progress)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking lecture_progress changes.

  ## Examples

      iex> change_lecture_progress(lecture_progress)
      %Ecto.Changeset{data: %LectureProgress{}}

  """
  def change_lecture_progress(%LectureProgress{} = lecture_progress, attrs \\ %{}) do
    LectureProgress.changeset(lecture_progress, attrs)
  end

  defp persist_progress(user, lecture, position_seconds, explicit_complete?) do
    if Enrollments.can_access_lecture?(user, lecture) do
      position =
        position_seconds
        |> trunc()
        |> max(0)
        |> min(lecture.duration_seconds)

      completed? =
        explicit_complete? or
          position >= completion_position(lecture.duration_seconds)

      case Repo.transaction(fn ->
             Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [user.id, lecture.id])

             progress =
               LectureProgress
               |> where(
                 [progress],
                 progress.user_id == ^user.id and progress.lecture_id == ^lecture.id
               )
               |> lock("FOR UPDATE")
               |> Repo.one()

             previous_status = progress && progress.status
             progress = progress || %LectureProgress{user_id: user.id, lecture_id: lecture.id}
             attrs = progress_attrs(progress, position, completed?)

             saved =
               progress
               |> LectureProgress.changeset(attrs)
               |> Repo.insert_or_update!()

             {saved, previous_status != :completed and saved.status == :completed}
           end) do
        {:ok, {progress, newly_completed?}} ->
          events =
            if newly_completed? do
              completion_events(user, lecture, progress)
            else
              []
            end

          broadcast_events(user, events)
          {:ok, progress, events}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, changeset}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :forbidden}
    end
  end

  defp progress_attrs(%LectureProgress{status: :completed} = progress, position, _completed?) do
    %{
      status: :completed,
      last_position_seconds: max(progress.last_position_seconds, position),
      completed_at: progress.completed_at
    }
  end

  defp progress_attrs(progress, position, completed?) do
    position = max(progress.last_position_seconds || 0, position)

    if completed? do
      %{
        status: :completed,
        last_position_seconds: position,
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    else
      %{status: :in_progress, last_position_seconds: position, completed_at: nil}
    end
  end

  defp completion_events(user, lecture, progress) do
    module = Repo.get!(CourseModule, lecture.module_id)
    course = Repo.get!(Course, module.course_id)

    [{:lecture_completed, progress}]
    |> maybe_add_event(module_complete?(user, module), {:module_completed, module})
    |> maybe_add_event(course_complete?(user, course), {:course_completed, course})
  end

  def module_complete?(user, %CourseModule{id: module_id}) do
    completion_counts(user.id, where(Lecture, [lecture], lecture.module_id == ^module_id))
  end

  def course_complete?(user, %Course{id: course_id}) do
    lectures =
      Lecture
      |> join(:inner, [lecture], module in CourseModule, on: module.id == lecture.module_id)
      |> where([_lecture, module], module.course_id == ^course_id)

    completion_counts(user.id, lectures)
  end

  defp completion_counts(user_id, lectures_query) do
    lecture_ids = from(lecture in lectures_query, select: lecture.id)
    total = Repo.aggregate(lectures_query, :count)

    completed =
      LectureProgress
      |> where(
        [progress],
        progress.user_id == ^user_id and
          progress.status == :completed and
          progress.lecture_id in subquery(lecture_ids)
      )
      |> Repo.aggregate(:count)

    total > 0 and completed == total
  end

  defp broadcast_events(user, events) do
    Enum.each(events, fn event ->
      Phoenix.PubSub.broadcast(Wasomi.PubSub, learning_topic(user.id), event)
    end)

    Certificates.enqueue_for_completion_events(user, events)
  end

  defp maybe_add_event(events, true, event), do: events ++ [event]
  defp maybe_add_event(events, false, _event), do: events

  defp completion_position(duration_seconds),
    do: duration_seconds * @completion_ratio

  defp percentage(_completed, 0), do: 0
  defp percentage(completed, total), do: round(completed / total * 100)

  defp progress_status(progress, lecture_id) do
    case progress[lecture_id] do
      %LectureProgress{status: status} -> status
      nil -> :not_started
    end
  end

  defp course_lectures(%Course{modules: modules}) when is_list(modules) do
    Enum.flat_map(modules, & &1.lectures)
  end

  defp learning_topic(user_id), do: "learning:user:#{user_id}"
  defp id_for(%{id: id}), do: id
  defp id_for(id), do: id
end
