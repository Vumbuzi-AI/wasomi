defmodule Wasomi.Catalog.Analytics do
  @moduledoc """
  Aggregate queries for the admin analytics dashboard.

  Unlike the other contexts, this module deliberately reaches across
  Enrollments, Learning, Assessments, and Payments rather than owning its
  own tables — it exists purely to answer "how is this course doing"
  questions that no single context can answer alone.

  Every function accepts the same `opts`:

    * `:course_id` - scope to a single course (default: every course)
    * `:from` / `:to` - a `Date` range applied to the *activity* being
      measured (lecture completion, quiz submission, or payment date).
      This does not affect who counts as an eligible learner for
      `module_completion_rates/1` — that denominator is always "currently
      active enrollments", regardless of the date range, so a rate can't
      be inflated by narrowing the window to exclude non-completers.
  """

  import Ecto.Query, warn: false

  alias Wasomi.Assessments.{Quiz, QuizSubmission}
  alias Wasomi.Catalog.{Course, CourseModule, Lecture}
  alias Wasomi.Certificates
  alias Wasomi.Enrollments
  alias Wasomi.Learning
  alias Wasomi.Learning.LectureProgress
  alias Wasomi.Payments.Payment
  alias Wasomi.Repo

  @doc """
  Percentage (0-100) of currently-active learners who completed every
  lecture in each module, keyed by `module_id`.

  A module with no lectures is omitted (nothing to complete).
  """
  def module_completion_rates(opts \\ []) do
    course_id = Keyword.get(opts, :course_id)
    {from, to} = date_bounds(opts)

    modules =
      CourseModule
      |> filter_module_course(course_id)
      |> select([m], %{id: m.id, course_id: m.course_id, title: m.title})
      |> Repo.all()

    lecture_counts =
      Lecture
      |> join(:inner, [l], m in CourseModule, on: m.id == l.module_id)
      |> filter_module_course(course_id, m_binding: 1)
      |> group_by([l, m], m.id)
      |> select([l, m], {m.id, count(l.id)})
      |> Repo.all()
      |> Map.new()

    completed_learners_by_module =
      LectureProgress
      |> join(:inner, [p], l in Lecture, on: l.id == p.lecture_id)
      |> join(:inner, [p, l], m in CourseModule, on: m.id == l.module_id)
      |> where([p], p.status == :completed)
      |> filter_module_course(course_id, m_binding: 2)
      |> filter_range(:completed_at, from, to)
      |> group_by([p, l, m], [m.id, p.user_id])
      |> select([p, l, m], {m.id, p.user_id, count(p.id)})
      |> Repo.all()
      |> Enum.reduce(%{}, fn {module_id, _user_id, completed}, acc ->
        if completed == Map.get(lecture_counts, module_id, -1) do
          Map.update(acc, module_id, 1, &(&1 + 1))
        else
          acc
        end
      end)

    active_by_course = Enrollments.count_active_by_course()

    modules
    |> Enum.filter(&(Map.get(lecture_counts, &1.id, 0) > 0))
    |> Map.new(fn module ->
      eligible = Map.get(active_by_course, module.course_id, 0)
      completed = Map.get(completed_learners_by_module, module.id, 0)
      rate = if eligible > 0, do: round(completed / eligible * 100), else: 0

      {module.id,
       %{
         title: module.title,
         course_id: module.course_id,
         rate_percent: rate,
         completed_learners: completed,
         eligible_learners: eligible
       }}
    end)
  end

  @doc """
  Average quiz score (0-100) per module, keyed by `module_id`. Averages
  every submission in range, not just each learner's best attempt.
  """
  def average_quiz_scores(opts \\ []) do
    course_id = Keyword.get(opts, :course_id)
    {from, to} = date_bounds(opts)

    QuizSubmission
    |> join(:inner, [s], q in Quiz, on: q.id == s.quiz_id)
    |> join(:inner, [s, q], m in CourseModule, on: m.id == q.module_id)
    |> filter_module_course(course_id, m_binding: 2)
    |> filter_range(:submitted_at, from, to)
    |> group_by([s, q, m], [m.id, q.title])
    |> select([s, q, m], %{
      module_id: m.id,
      quiz_title: q.title,
      average_score_percent: avg(s.score_percent),
      submissions: count(s.id)
    })
    |> Repo.all()
    |> Map.new(fn row ->
      {row.module_id, %{row | average_score_percent: to_rounded_float(row.average_score_percent)}}
    end)
  end

  @doc """
  For each lecture, the average last known playback position among
  learners who started but did not finish it (`:in_progress`), expressed
  in seconds and as a percentage of the lecture's duration. Sorted with
  the earliest drop-off points first, since those are the lectures where
  learners give up soonest.

  There is no dedicated watch-event log in this app, so
  `last_position_seconds` (last saved playback position) is the closest
  available signal — this approximates drop-off, it does not chart a
  second-by-second abandonment curve.
  """
  def video_dropoff_seconds(opts \\ []) do
    course_id = Keyword.get(opts, :course_id)
    {from, to} = date_bounds(opts)

    LectureProgress
    |> join(:inner, [p], l in Lecture, on: l.id == p.lecture_id)
    |> join(:inner, [p, l], m in CourseModule, on: m.id == l.module_id)
    |> where([p], p.status == :in_progress)
    |> filter_module_course(course_id, m_binding: 2)
    |> filter_range(:updated_at, from, to)
    |> group_by([p, l, m], [l.id, l.title, l.duration_seconds])
    |> select([p, l, m], %{
      lecture_id: l.id,
      title: l.title,
      duration_seconds: l.duration_seconds,
      avg_position_seconds: avg(p.last_position_seconds),
      viewers: count(p.id)
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      avg_position = to_rounded_float(row.avg_position_seconds)

      dropoff_percent =
        if row.duration_seconds > 0, do: round(avg_position / row.duration_seconds * 100), else: 0

      row
      |> Map.put(:avg_position_seconds, avg_position)
      |> Map.put(:dropoff_percent, dropoff_percent)
    end)
    |> Enum.sort_by(& &1.dropoff_percent)
  end

  @doc """
  Successful revenue, in minor units, summed by calendar month, ordered
  chronologically. Mirrors `Payments.revenue_minor_by_course/0`'s shape,
  scoped by course and/or date range.
  """
  def monthly_revenue(opts \\ []) do
    course_id = Keyword.get(opts, :course_id)
    {from, to} = date_bounds(opts)

    Payment
    |> where([p], p.status == :successful)
    |> filter_payment_course(course_id)
    |> filter_range(:paid_at, from, to)
    |> group_by([p], fragment("date_trunc('month', ?)", p.paid_at))
    |> select([p], %{
      month: fragment("date_trunc('month', ?)", p.paid_at),
      revenue_minor: sum(p.amount_minor)
    })
    |> order_by([p], fragment("date_trunc('month', ?)", p.paid_at))
    |> Repo.all()
  end

  @doc """
  Successful revenue, in minor units, per course, richest first. Same
  `:course_id`/`:from`/`:to` scoping as every other function here — passing
  `:course_id` just returns that one course's row, so callers building a
  "top courses" breakdown normally leave it unset.
  """
  def revenue_by_course(opts \\ []) do
    course_id = Keyword.get(opts, :course_id)
    {from, to} = date_bounds(opts)

    Payment
    |> where([p], p.status == :successful)
    |> filter_payment_course(course_id)
    |> filter_range(:paid_at, from, to)
    |> join(:inner, [p], c in Course, on: c.id == p.course_id)
    |> group_by([p, c], c.id)
    |> select([p, c], %{course_id: c.id, title: c.title, revenue_minor: sum(p.amount_minor)})
    |> order_by([p, c], desc: sum(p.amount_minor))
    |> Repo.all()
  end

  @doc """
  Percentage (0-100) of quiz submissions that passed, keyed by `course_id`.
  """
  def quiz_pass_rate_by_course(opts \\ []) do
    course_id = Keyword.get(opts, :course_id)
    {from, to} = date_bounds(opts)

    QuizSubmission
    |> join(:inner, [s], q in Quiz, on: q.id == s.quiz_id)
    |> join(:inner, [s, q], m in CourseModule, on: m.id == q.module_id)
    |> filter_module_course(course_id, m_binding: 2)
    |> filter_range(:submitted_at, from, to)
    |> group_by([s, q, m], m.course_id)
    |> select([s, q, m], %{
      course_id: m.course_id,
      passed: fragment("count(*) filter (where ?)", s.passed),
      total: count(s.id)
    })
    |> Repo.all()
    |> Map.new(fn row -> {row.course_id, percent(row.passed, row.total)} end)
  end

  @doc """
  Average module completion rate per course, keyed by `course_id` — the
  simple mean of `module_completion_rates/1`'s per-module rates for that
  course (not a weighted sum: every module in a course shares the same
  "active enrollees" denominator, so weighting by it would just multiply
  the same number in rather than add signal).
  """
  def completion_rate_by_course(opts \\ []) do
    opts
    |> module_completion_rates()
    |> Map.values()
    |> Enum.group_by(& &1.course_id, & &1.rate_percent)
    |> Map.new(fn {course_id, rates} -> {course_id, average(rates)} end)
  end

  @doc """
  One row per course combining enrollment, completion rate, quiz pass
  rate, and revenue — the org-wide course leaderboard for the analytics
  overview. Same `:course_id`/`:from`/`:to` scoping as the rest of this
  module. Sorted richest-first by revenue.
  """
  def course_scorecards(opts \\ []) do
    course_id = Keyword.get(opts, :course_id)

    courses =
      Course
      |> filter_course(course_id)
      |> select([c], %{id: c.id, title: c.title, slug: c.slug})
      |> Repo.all()

    revenue_by_course = opts |> revenue_by_course() |> Map.new(&{&1.course_id, &1.revenue_minor})
    completion_by_course = completion_rate_by_course(opts)
    pass_rate_by_course = quiz_pass_rate_by_course(opts)
    enrolled_by_course = Enrollments.count_active_by_course()

    courses
    |> Enum.map(fn course ->
      %{
        course_id: course.id,
        title: course.title,
        slug: course.slug,
        enrolled: Map.get(enrolled_by_course, course.id, 0),
        completion_rate_percent: Map.get(completion_by_course, course.id, 0),
        quiz_pass_rate_percent: Map.get(pass_rate_by_course, course.id, 0),
        revenue_minor: Map.get(revenue_by_course, course.id, 0)
      }
    end)
    |> Enum.sort_by(& &1.revenue_minor, :desc)
  end

  @doc """
  The admin conversion funnel: checkout started → paid → active →
  completed → certified. Optionally scoped to one course via `:course_id`.

  Deliberately **not** scoped by `:from`/`:to` like the rest of this
  module — the five steps don't share a common timestamp (a payment's
  `paid_at`, an enrollment's `activated_at`, a certificate's `issued_at`
  all measure different moments), so windowing each step independently by
  the same date range would silently misrepresent the conversion rate
  between them. This is always an all-time snapshot.
  """
  def funnel(opts \\ []) do
    course_id = Keyword.get(opts, :course_id)

    checkout_started =
      Payment
      |> filter_payment_course(course_id)
      |> Repo.aggregate(:count)

    paid =
      Payment
      |> where([p], p.status == :successful)
      |> filter_payment_course(course_id)
      |> Repo.aggregate(:count)

    active =
      if course_id,
        do: Enrollments.count_active_for_course(course_id),
        else: Enrollments.count_active()

    completed = Learning.count_course_completions(course_id: course_id)
    certified = Certificates.count_course_certificates(course_id: course_id)

    [
      %{step: "Checkout started", count: checkout_started},
      %{step: "Paid", count: paid},
      %{step: "Active", count: active},
      %{step: "Completed", count: completed},
      %{step: "Certified", count: certified}
    ]
  end

  defp filter_course(query, nil), do: query
  defp filter_course(query, course_id), do: where(query, [c], c.id == ^course_id)

  defp percent(_numerator, 0), do: 0
  defp percent(numerator, denominator), do: round(numerator / denominator * 100)

  defp average([]), do: 0
  defp average(numbers), do: round(Enum.sum(numbers) / length(numbers))

  # `CourseModule` is binding 0 when queried directly (no course_id arg
  # needed beyond that), or binding 1/2 once joined in behind Lecture or
  # LectureProgress/QuizSubmission — since Ecto's `where/3` binding list
  # must name every position up to the one you use, the two call shapes
  # need their own clauses rather than one generic helper.
  defp filter_module_course(query, nil), do: query
  defp filter_module_course(query, course_id), do: where(query, [m], m.course_id == ^course_id)

  defp filter_module_course(query, nil, _opts), do: query

  defp filter_module_course(query, course_id, m_binding: 1),
    do: where(query, [_l, m], m.course_id == ^course_id)

  defp filter_module_course(query, course_id, m_binding: 2),
    do: where(query, [_p, _l, m], m.course_id == ^course_id)

  defp filter_payment_course(query, nil), do: query
  defp filter_payment_course(query, course_id), do: where(query, [p], p.course_id == ^course_id)

  # Binding 0 is always the "subject" table (LectureProgress, QuizSubmission,
  # or Payment) across every query this module runs, so a single pair of
  # helpers keyed by field name covers all of them.
  defp filter_range(query, field, from, to) do
    query
    |> filter_from(field, from)
    |> filter_to(field, to)
  end

  defp filter_from(query, _field, nil), do: query
  defp filter_from(query, field, from), do: where(query, [x], field(x, ^field) >= ^from)

  defp filter_to(query, _field, nil), do: query
  defp filter_to(query, field, to), do: where(query, [x], field(x, ^field) <= ^to)

  defp date_bounds(opts) do
    {start_of_day(Keyword.get(opts, :from)), end_of_day(Keyword.get(opts, :to))}
  end

  defp start_of_day(nil), do: nil
  defp start_of_day(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  defp end_of_day(nil), do: nil
  defp end_of_day(%Date{} = date), do: DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

  defp to_rounded_float(nil), do: 0.0

  defp to_rounded_float(%Decimal{} = decimal),
    do: decimal |> Decimal.round(1) |> Decimal.to_float()

  defp to_rounded_float(number) when is_number(number), do: number * 1.0
end
