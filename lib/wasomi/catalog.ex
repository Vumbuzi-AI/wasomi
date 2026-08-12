defmodule Wasomi.Catalog do
  @moduledoc """
  The Catalog context.
  """

  import Ecto.Query, warn: false
  alias Wasomi.Repo

  alias Wasomi.Catalog.{
    Course,
    CourseModule,
    Lecture,
    LectureQuestion,
    LectureResource,
    LectureTranscript,
    PublishGuard
  }

  alias Wasomi.Catalog.Workers.TranscribeLecture
  alias Wasomi.Paginate

  @doc """
  Returns the list of courses, newest first, optionally filtered.

  `position` is just an auto-incrementing creation counter (courses have no
  manual reordering UI, unlike modules and lectures), so sorting by it
  buried new courses at the bottom — sort by `inserted_at` instead.

  ## Options

    * `:status` - only courses in this status (`:draft`, `:published`, `:archived`).
    * `:search` - case-insensitive match against title or slug.

  ## Examples

      iex> list_courses()
      [%Course{}, ...]

      iex> list_courses(status: :published, search: "gs1")
      [%Course{}, ...]

  """
  def list_courses(opts \\ []) do
    opts
    |> filtered_courses_query()
    |> Repo.all()
  end

  @doc """
  Returns a `Wasomi.Paginate.Page` of courses, same filtering as
  `list_courses/1` plus `:page`/`:page_size`.

  ## Examples

      iex> list_courses_page(status: :published, page: 2, page_size: 9)
      %Wasomi.Paginate{entries: [%Course{}, ...], page: 2, ...}

  """
  def list_courses_page(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 9)

    opts
    |> filtered_courses_query()
    |> Paginate.paginate(page, page_size)
  end

  defp filtered_courses_query(opts) do
    Course
    |> order_by([course], desc: course.inserted_at, desc: course.id)
    |> filter_by_status(Keyword.get(opts, :status))
    |> filter_by_search(Keyword.get(opts, :search))
  end

  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, status), do: where(query, [course], course.status == ^status)

  defp filter_by_search(query, search) when search in [nil, ""], do: query

  defp filter_by_search(query, search) do
    pattern = "%#{search}%"
    where(query, [course], ilike(course.title, ^pattern) or ilike(course.slug, ^pattern))
  end

  @doc """
  Counts all courses regardless of status. Used by the admin overview.
  """
  def count_courses, do: Repo.aggregate(Course, :count)

  @doc """
  Counts courses currently in the given status (`:draft` or `:published`).
  """
  def count_courses(status) do
    Course
    |> where([course], course.status == ^status)
    |> Repo.aggregate(:count)
  end

  @doc """
  Aggregate course counts (total, published, draft) for the admin courses
  stat cards, computed in a single grouped query.
  """
  def course_stats do
    by_status =
      Course
      |> group_by([course], course.status)
      |> select([course], {course.status, count(course.id)})
      |> Repo.all()
      |> Map.new()

    %{
      total: Enum.reduce(by_status, 0, fn {_status, count}, acc -> acc + count end),
      published: Map.get(by_status, :published, 0),
      draft: Map.get(by_status, :draft, 0)
    }
  end

  @doc """
  Gets a single course by id with its ordered modules and lectures preloaded.
  """
  def get_course_with_outline!(id) do
    Course
    |> Repo.get!(id)
    |> preload_outline()
  end

  @doc """
  Lists published courses in their public display order.
  """
  def list_published_courses do
    Course
    |> where([course], course.status == :published)
    |> order_by([course], asc: course.position, asc: course.title)
    |> Repo.all()
    |> preload_outline()
  end

  @doc """
  Gets a single course.

  Raises `Ecto.NoResultsError` if the Course does not exist.

  ## Examples

      iex> get_course!(123)
      %Course{}

      iex> get_course!(456)
      ** (Ecto.NoResultsError)

  """
  def get_course!(id), do: Repo.get!(Course, id)

  @doc """
  Gets a course by slug, including ordered modules and lectures.
  """
  def get_course_by_slug!(slug) when is_binary(slug) do
    Course
    |> Repo.get_by!(slug: slug)
    |> preload_outline()
  end

  @doc """
  Gets a published course by slug, including ordered modules and lectures.
  """
  def get_published_course_by_slug!(slug) when is_binary(slug) do
    Course
    |> where([course], course.status == :published and course.slug == ^slug)
    |> Repo.one!()
    |> preload_outline()
  end

  @doc """
  Converts the persisted integer minor units into a currency-aware value.
  """
  def price(%Course{price_minor: amount, currency: currency}) do
    Money.new(amount, currency)
  end

  @doc """
  Formats a course price for public display.
  """
  def format_price(%Course{} = course) do
    course
    |> price()
    |> Money.to_string(symbol: false, code: true)
  end

  def lecture_count(%Course{modules: modules}) when is_list(modules) do
    Enum.sum(Enum.map(modules, &length(&1.lectures)))
  end

  def duration_seconds(%Course{modules: modules}) when is_list(modules) do
    modules
    |> Enum.flat_map(& &1.lectures)
    |> Enum.map(& &1.duration_seconds)
    |> Enum.sum()
  end

  defp preload_outline(course_or_courses) do
    modules_query = from(module in CourseModule, order_by: [asc: module.position])

    lectures_query =
      from(lecture in Lecture,
        order_by: [asc: lecture.position],
        preload: [
          resources: ^ordered_resources_query(),
          questions: ^ordered_questions_query()
        ]
      )

    Repo.preload(course_or_courses,
      modules: {modules_query, [:quiz, lectures: lectures_query]}
    )
  end

  @doc """
  Preloads a lecture's resources and questions in their persisted display order.
  """
  def preload_lecture_content(%Lecture{} = lecture) do
    Repo.preload(lecture,
      resources: ordered_resources_query(),
      questions: ordered_questions_query()
    )
  end

  defp ordered_resources_query do
    from(resource in LectureResource, order_by: [asc: resource.position])
  end

  defp ordered_questions_query do
    from(question in LectureQuestion, order_by: [asc: question.position])
  end

  @doc """
  Creates a course.

  ## Examples

      iex> create_course(%{field: value})
      {:ok, %Course{}}

      iex> create_course(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_course(attrs \\ %{}) do
    attrs =
      attrs
      |> put_generated_slug()
      |> put_default_position()

    %Course{}
    |> Course.changeset(attrs)
    |> Repo.insert()
  end

  defp put_generated_slug(attrs) do
    attrs = Map.new(attrs)
    slug_key = if Map.has_key?(attrs, "title"), do: "slug", else: :slug
    title_key = if Map.has_key?(attrs, "title"), do: "title", else: :title

    if blank?(Map.get(attrs, slug_key)) do
      slug =
        attrs
        |> Map.get(title_key)
        |> slugify()
        |> unique_slug()

      Map.put(attrs, slug_key, slug)
    else
      attrs
    end
  end

  defp put_default_position(attrs) do
    attrs = Map.new(attrs)
    position_key = if Map.has_key?(attrs, "title"), do: "position", else: :position

    if blank?(Map.get(attrs, position_key)) do
      Map.put(attrs, position_key, next_course_position())
    else
      attrs
    end
  end

  defp next_course_position do
    (Repo.aggregate(Course, :max, :position) || 0) + 1
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp slugify(nil), do: ""

  defp slugify(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.trim()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.replace(~r/[\s-]+/, "-")
    |> String.trim("-")
  end

  defp unique_slug(base) do
    base = if base in [nil, ""], do: "course", else: base
    find_available_slug(base, 1)
  end

  defp find_available_slug(base, attempt) do
    candidate = if attempt == 1, do: base, else: "#{base}-#{attempt}"

    if Repo.exists?(from course in Course, where: course.slug == ^candidate) do
      find_available_slug(base, attempt + 1)
    else
      candidate
    end
  end

  @doc """
  Updates a course.

  ## Examples

      iex> update_course(course, %{field: new_value})
      {:ok, %Course{}}

      iex> update_course(course, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_course(%Course{} = course, attrs) do
    course
    |> Course.changeset(reject_guarded_statuses(attrs))
    |> Repo.update()
  end

  # Status is only reachable via its own dedicated function (publish_course/1,
  # unpublish_course/1, archive_course/1) — silently dropped here rather than
  # raised, since the edit form never submits :status itself.
  defp reject_guarded_statuses(attrs) do
    Map.drop(Map.new(attrs), [:status, "status"])
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking course changes.

  ## Examples

      iex> change_course(course)
      %Ecto.Changeset{data: %Course{}}

  """
  def change_course(%Course{} = course, attrs \\ %{}) do
    Course.changeset(course, attrs)
  end

  @doc """
  Updates a course's certificate configuration (issuer, signatory, signature).
  """
  def update_course_certificate(%Course{} = course, attrs) do
    course
    |> Course.certificate_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking course certificate configuration changes.
  """
  def change_course_certificate(%Course{} = course, attrs \\ %{}) do
    Course.certificate_changeset(course, attrs)
  end

  @doc """
  The only path that flips a course's status to `:published`.

  Row-locks the course and re-checks it inside a transaction, so two
  concurrent publish attempts can't both slip through between check and
  write. Re-fetches with the current outline (never trusts a stale
  in-memory struct), then runs `PublishGuard` and `Course.publish_changeset/1`
  as an independent second check. On failure, status is left unchanged and
  `{:error, issues}` lists everything missing.
  """
  def publish_course(%Course{} = course) do
    Repo.transaction(fn ->
      course =
        Course
        |> Repo.get!(course.id, lock: "FOR UPDATE")
        |> preload_outline()

      case PublishGuard.check(course) do
        :ok ->
          case course |> Course.publish_changeset() |> Repo.update() do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end

        {:error, issues} ->
          Repo.rollback(issues)
      end
    end)
  end

  @doc """
  The only path that moves a published course back to `:draft`.

  For pulling a live course back for revision without retiring it (a
  correction, a pricing fix, a compliance hold) — the course is coming
  back, unlike `archive_course/1`. Unconditional: no checklist, and
  enrolled learners keep their normal access regardless of status.
  Re-publishing goes through `publish_course/1` again, so the readiness
  checklist re-applies.
  """
  def unpublish_course(%Course{} = course) do
    course
    |> Course.changeset(%{status: :draft})
    |> Repo.update()
  end

  @doc """
  The only path that flips a course's status to `:archived`.

  Unconditional — no checklist, and it doesn't check for learners still in
  progress. `Enrollments.can_access_course?/2` is gated purely by
  enrollment, never by `Course.status`, so already-enrolled learners keep
  their access; archiving only removes the course from public browsing and
  blocks new enrollments. Callers that want to warn an admin about
  in-progress learners should query `Learning.count_incomplete_enrollees/1`
  separately rather than have this block or fail on it.
  """
  def archive_course(%Course{} = course) do
    course
    |> Course.changeset(%{status: :archived})
    |> Repo.update()
  end

  @doc """
  Returns the list of modules.

  ## Examples

      iex> list_modules()
      [%CourseModule{}, ...]

  """
  def list_modules do
    CourseModule
    |> order_by([module], asc: module.course_id, asc: module.position)
    |> Repo.all()
  end

  @doc """
  Gets a single course_module.

  Raises `Ecto.NoResultsError` if the Course module does not exist.

  ## Examples

      iex> get_course_module!(123)
      %CourseModule{}

      iex> get_course_module!(456)
      ** (Ecto.NoResultsError)

  """
  def get_course_module!(id), do: Repo.get!(CourseModule, id)

  @doc """
  Creates a course_module.

  ## Examples

      iex> create_course_module(%{field: value})
      {:ok, %CourseModule{}}

      iex> create_course_module(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_course_module(attrs \\ %{}) do
    %CourseModule{}
    |> CourseModule.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a course_module.

  ## Examples

      iex> update_course_module(course_module, %{field: new_value})
      {:ok, %CourseModule{}}

      iex> update_course_module(course_module, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_course_module(%CourseModule{} = course_module, attrs) do
    course_module
    |> CourseModule.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Reorders all modules in a course using the given module ids.
  """
  def reorder_course_modules(course_id, module_ids) when is_list(module_ids) do
    with {:ok, module_ids} <- normalize_ids(module_ids),
         {:ok, modules} <- fetch_reorderable(CourseModule, :course_id, course_id, module_ids) do
      reorder_records(modules, module_ids, CourseModule)
    end
  end

  @doc """
  Deletes a course_module.

  ## Examples

      iex> delete_course_module(course_module)
      {:ok, %CourseModule{}}

      iex> delete_course_module(course_module)
      {:error, %Ecto.Changeset{}}

  """
  def delete_course_module(%CourseModule{} = course_module) do
    Repo.delete(course_module)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking course_module changes.

  ## Examples

      iex> change_course_module(course_module)
      %Ecto.Changeset{data: %CourseModule{}}

  """
  def change_course_module(%CourseModule{} = course_module, attrs \\ %{}) do
    CourseModule.changeset(course_module, attrs)
  end

  @doc """
  Returns the list of lectures.

  ## Examples

      iex> list_lectures()
      [%Lecture{}, ...]

  """
  def list_lectures do
    Lecture
    |> order_by([lecture], asc: lecture.module_id, asc: lecture.position)
    |> Repo.all()
  end

  @doc """
  Gets a single lecture.

  Raises `Ecto.NoResultsError` if the Lecture does not exist.

  ## Examples

      iex> get_lecture!(123)
      %Lecture{}

      iex> get_lecture!(456)
      ** (Ecto.NoResultsError)

  """
  def get_lecture!(id), do: Repo.get!(Lecture, id)

  @doc """
  Gets a single lecture resource, with its lecture preloaded.

  Raises `Ecto.NoResultsError` if the LectureResource does not exist.
  """
  def get_lecture_resource!(id) do
    LectureResource
    |> Repo.get!(id)
    |> Repo.preload(:lecture)
  end

  @doc """
  Creates a lecture.

  ## Examples

      iex> create_lecture(%{field: value})
      {:ok, %Lecture{}}

      iex> create_lecture(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_lecture(attrs \\ %{}) do
    %Lecture{}
    |> Lecture.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a lecture.

  ## Examples

      iex> update_lecture(lecture, %{field: new_value})
      {:ok, %Lecture{}}

      iex> update_lecture(lecture, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_lecture(%Lecture{} = lecture, attrs) do
    lecture
    |> Lecture.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a lecture and replaces its ordered resources and learner questions atomically.
  """
  def update_lecture_content(%Lecture{} = lecture, lecture_attrs, resources, questions)
      when is_list(resources) and is_list(questions) do
    previous_asset_id = lecture.video_asset_id

    Repo.transaction(fn ->
      with {:ok, lecture} <- Repo.update(Lecture.changeset(lecture, lecture_attrs)),
           :ok <- delete_lecture_content(lecture.id),
           {:ok, _resources} <- insert_resources(lecture.id, resources),
           {:ok, _questions} <- insert_questions(lecture.id, questions) do
        preload_lecture_content(lecture)
      else
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
      end
    end)
    |> maybe_enqueue_transcript(previous_asset_id)
  end

  defp delete_lecture_content(lecture_id) do
    Repo.delete_all(from(resource in LectureResource, where: resource.lecture_id == ^lecture_id))
    Repo.delete_all(from(question in LectureQuestion, where: question.lecture_id == ^lecture_id))
    :ok
  end

  defp insert_resources(lecture_id, resources) do
    insert_content_records(LectureResource, lecture_id, resources)
  end

  defp insert_questions(lecture_id, questions) do
    insert_content_records(LectureQuestion, lecture_id, questions)
  end

  defp insert_content_records(schema, lecture_id, records) do
    records
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {attrs, position}, {:ok, inserted} ->
      changeset =
        attrs
        |> Map.new()
        |> Map.merge(%{lecture_id: lecture_id, position: position})
        |> then(&schema.changeset(struct(schema), &1))

      case Repo.insert(changeset) do
        {:ok, record} -> {:cont, {:ok, [record | inserted]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  def create_lecture_content(lecture_attrs, resources, questions)
      when is_list(resources) and is_list(questions) do
    Repo.transaction(fn ->
      with {:ok, lecture} <- Repo.insert(Lecture.changeset(%Lecture{}, lecture_attrs)),
           {:ok, _resources} <- insert_resources(lecture.id, resources),
           {:ok, _questions} <- insert_questions(lecture.id, questions) do
        Repo.preload(lecture, [:resources, :questions])
      else
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
      end
    end)
    |> maybe_enqueue_transcript(nil)
  end

  # Only (re-)enqueues transcription when the lecture's video actually
  # changed to a real asset — otherwise every unrelated edit (title,
  # resources, reordering) on an already-transcribed lecture would restart
  # transcription from scratch.
  defp maybe_enqueue_transcript(
         {:ok, %Lecture{video_asset_id: asset_id} = lecture},
         previous_asset_id
       )
       when is_binary(asset_id) and asset_id != "" and asset_id != previous_asset_id do
    TranscribeLecture.enqueue(lecture.id)
    {:ok, lecture}
  end

  defp maybe_enqueue_transcript(result, _previous_asset_id), do: result

  @doc """
  Returns the transcript for a lecture, or `nil` if none has been generated yet.
  """
  def get_lecture_transcript(lecture_id) do
    Repo.get_by(LectureTranscript, lecture_id: lecture_id)
  end

  @doc """
  Creates or updates a lecture's transcript in one shot, keyed on `lecture_id`.

  Used by `Wasomi.Catalog.Workers.TranscribeLecture` to move a transcript
  through `:pending` -> `:processing` -> `:ready`/`:failed` without needing
  to look up whether a row already exists first.
  """
  def upsert_lecture_transcript(lecture_id, attrs) do
    %LectureTranscript{}
    |> LectureTranscript.changeset(Map.put(attrs, :lecture_id, lecture_id))
    |> Repo.insert(
      on_conflict: {:replace, [:status, :text, :error, :updated_at]},
      conflict_target: :lecture_id,
      returning: true
    )
  end

  def lecture_resource_count(%Lecture{resources: resources}) when is_list(resources),
    do: length(resources)

  def lecture_resource_count(%Lecture{} = lecture),
    do:
      Repo.aggregate(
        from(resource in LectureResource, where: resource.lecture_id == ^lecture.id),
        :count
      )

  def lecture_question_count(%Lecture{questions: questions}) when is_list(questions),
    do: length(questions)

  def lecture_question_count(%Lecture{} = lecture),
    do:
      Repo.aggregate(
        from(question in LectureQuestion, where: question.lecture_id == ^lecture.id),
        :count
      )

  @doc """
  Reorders all lectures in a module using the given lecture ids.
  """
  def reorder_module_lectures(module_id, lecture_ids) when is_list(lecture_ids) do
    with {:ok, lecture_ids} <- normalize_ids(lecture_ids),
         {:ok, lectures} <- fetch_reorderable(Lecture, :module_id, module_id, lecture_ids) do
      reorder_records(lectures, lecture_ids, Lecture)
    end
  end

  @doc """
  Deletes a lecture.

  ## Examples

      iex> delete_lecture(lecture)
      {:ok, %Lecture{}}

      iex> delete_lecture(lecture)
      {:error, %Ecto.Changeset{}}

  """
  def delete_lecture(%Lecture{} = lecture) do
    Repo.delete(lecture)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking lecture changes.

  ## Examples

      iex> change_lecture(lecture)
      %Ecto.Changeset{data: %Lecture{}}

  """
  def change_lecture(%Lecture{} = lecture, attrs \\ %{}) do
    Lecture.changeset(lecture, attrs)
  end

  defp normalize_ids(ids) do
    ids
    |> Enum.reduce_while({:ok, []}, fn
      id, {:ok, ids} ->
        case parse_id(id) do
          {:ok, id} -> {:cont, {:ok, [id | ids]}}
          :error -> {:halt, {:error, :invalid_ids}}
        end
    end)
    |> case do
      {:ok, ids} ->
        ids = Enum.reverse(ids)

        if Enum.uniq(ids) == ids do
          {:ok, ids}
        else
          {:error, :invalid_ids}
        end

      error ->
        error
    end
  end

  defp fetch_reorderable(schema, parent_key, parent_id, ids) do
    with {:ok, parent_id} <- parse_id(parent_id) do
      records =
        schema
        |> where([record], field(record, ^parent_key) == ^parent_id)
        |> order_by([record], asc: record.position)
        |> Repo.all()

      if Enum.map(records, & &1.id) |> Enum.sort() == Enum.sort(ids) do
        {:ok, records}
      else
        {:error, :invalid_order}
      end
    end
  end

  defp parse_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} when id > 0 -> {:ok, id}
      _invalid -> :error
    end
  end

  defp parse_id(_id), do: :error

  defp reorder_records(records, ordered_ids, schema) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    offset = Enum.max(Enum.map(records, & &1.position), fn -> 0 end) + length(records) + 1

    Repo.transaction(fn ->
      records
      |> Enum.with_index(1)
      |> Enum.each(fn {record, index} ->
        from(item in schema, where: item.id == ^record.id)
        |> Repo.update_all(set: [position: offset + index, updated_at: now])
      end)

      ordered_ids
      |> Enum.with_index(1)
      |> Enum.each(fn {id, position} ->
        from(item in schema, where: item.id == ^id)
        |> Repo.update_all(set: [position: position, updated_at: now])
      end)
    end)
  end
end
