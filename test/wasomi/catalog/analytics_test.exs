defmodule Wasomi.Catalog.AnalyticsTest do
  use Wasomi.DataCase

  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures
  import Wasomi.LearningFixtures
  import Wasomi.PaymentsFixtures

  alias Wasomi.Assessments.QuizSubmission
  alias Wasomi.Catalog.Analytics
  alias Wasomi.Repo

  defp active_enrollment(course) do
    enrollment_fixture(user_id: user_fixture().id, course_id: course.id, status: :active)
  end

  defp submission_fixture(quiz, attrs) do
    {:ok, submission} =
      %QuizSubmission{}
      |> QuizSubmission.changeset(
        Enum.into(attrs, %{
          quiz_id: quiz.id,
          user_id: user_fixture().id,
          answers: %{},
          passed: true,
          submitted_at: ~U[2026-06-15 10:00:00Z]
        })
      )
      |> Repo.insert()

    submission
  end

  describe "module_completion_rates/1" do
    test "rate is the share of active enrollees who completed every lecture in the module" do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id)
      lecture_a = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
      lecture_b = lecture_fixture(module_id: module.id, position: 2, duration_seconds: 100)

      # Three active enrollees; only two finish both lectures in the module.
      active_enrollment(course)
      active_enrollment(course)
      active_enrollment(course)

      finisher_a = user_fixture()
      finisher_b = user_fixture()
      partial = user_fixture()

      for user <- [finisher_a, finisher_b] do
        lecture_progress_fixture(
          user_id: user.id,
          lecture_id: lecture_a.id,
          status: :completed,
          completed_at: ~U[2026-06-10 09:00:00Z]
        )

        lecture_progress_fixture(
          user_id: user.id,
          lecture_id: lecture_b.id,
          status: :completed,
          completed_at: ~U[2026-06-10 09:05:00Z]
        )
      end

      lecture_progress_fixture(
        user_id: partial.id,
        lecture_id: lecture_a.id,
        status: :completed,
        completed_at: ~U[2026-06-10 09:00:00Z]
      )

      rates = Analytics.module_completion_rates()

      assert %{
               title: _,
               course_id: course_id,
               rate_percent: 67,
               completed_learners: 2,
               eligible_learners: 3
             } = rates[module.id]

      assert course_id == course.id
    end

    test "a module with no lectures is omitted" do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id)
      active_enrollment(course)

      refute Map.has_key?(Analytics.module_completion_rates(), module.id)
    end

    test "scopes to a single course" do
      course_a = course_fixture()
      course_b = course_fixture()
      module_a = course_module_fixture(course_id: course_a.id)
      module_b = course_module_fixture(course_id: course_b.id)
      lecture_fixture(module_id: module_a.id)
      lecture_fixture(module_id: module_b.id)
      active_enrollment(course_a)
      active_enrollment(course_b)

      rates = Analytics.module_completion_rates(course_id: course_a.id)

      assert Map.has_key?(rates, module_a.id)
      refute Map.has_key?(rates, module_b.id)
    end

    test "a completion outside the date range is excluded from the numerator" do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id)
      lecture = lecture_fixture(module_id: module.id)
      active_enrollment(course)

      lecture_progress_fixture(
        lecture_id: lecture.id,
        status: :completed,
        completed_at: ~U[2026-01-01 00:00:00Z]
      )

      rates =
        Analytics.module_completion_rates(from: ~D[2026-06-01], to: ~D[2026-06-30])

      assert rates[module.id].completed_learners == 0
    end
  end

  describe "average_quiz_scores/1" do
    test "averages every submission in range, keyed by module_id" do
      module = course_module_fixture()
      quiz = quiz_fixture(module: module)

      submission_fixture(quiz, %{score_percent: 80})
      submission_fixture(quiz, %{score_percent: 60})

      assert %{average_score_percent: 70.0, submissions: 2} =
               Analytics.average_quiz_scores()[module.id]
    end

    test "excludes submissions outside the date range" do
      module = course_module_fixture()
      quiz = quiz_fixture(module: module)

      submission_fixture(quiz, %{score_percent: 100, submitted_at: ~U[2026-01-01 00:00:00Z]})
      submission_fixture(quiz, %{score_percent: 50, submitted_at: ~U[2026-06-15 00:00:00Z]})

      result =
        Analytics.average_quiz_scores(from: ~D[2026-06-01], to: ~D[2026-06-30])

      assert %{average_score_percent: 50.0, submissions: 1} = result[module.id]
    end
  end

  describe "video_dropoff_seconds/1" do
    test "averages the last known position among in-progress viewers, sorted earliest-first" do
      module = course_module_fixture()

      hard_lecture =
        lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)

      easy_lecture =
        lecture_fixture(module_id: module.id, position: 2, duration_seconds: 100)

      lecture_progress_fixture(
        lecture_id: hard_lecture.id,
        status: :in_progress,
        last_position_seconds: 10
      )

      lecture_progress_fixture(
        lecture_id: hard_lecture.id,
        status: :in_progress,
        last_position_seconds: 30
      )

      lecture_progress_fixture(
        lecture_id: easy_lecture.id,
        status: :in_progress,
        last_position_seconds: 80
      )

      # Completed viewers should not drag the "still watching" average down.
      lecture_progress_fixture(
        lecture_id: hard_lecture.id,
        status: :completed,
        completed_at: ~U[2026-06-10 09:00:00Z],
        last_position_seconds: 100
      )

      [first, second] = Analytics.video_dropoff_seconds()

      assert first.lecture_id == hard_lecture.id
      assert first.avg_position_seconds == 20.0
      assert first.dropoff_percent == 20

      assert second.lecture_id == easy_lecture.id
      assert second.dropoff_percent == 80
    end
  end

  describe "monthly_revenue/1" do
    test "sums successful payments by calendar month, ordered chronologically" do
      course = course_fixture()

      payment_fixture(
        course_id: course.id,
        status: :successful,
        amount_minor: 1_000,
        paid_at: ~U[2026-05-15 10:00:00Z]
      )

      payment_fixture(
        course_id: course.id,
        status: :successful,
        amount_minor: 500,
        paid_at: ~U[2026-05-20 10:00:00Z]
      )

      payment_fixture(
        course_id: course.id,
        status: :successful,
        amount_minor: 2_000,
        paid_at: ~U[2026-06-01 10:00:00Z]
      )

      # A pending payment must never count as revenue.
      payment_fixture(course_id: course.id, status: :pending)

      assert [
               %{month: %NaiveDateTime{year: 2026, month: 5}, revenue_minor: 1_500},
               %{month: %NaiveDateTime{year: 2026, month: 6}, revenue_minor: 2_000}
             ] = Analytics.monthly_revenue()
    end

    test "scopes to a single course" do
      course_a = course_fixture()
      course_b = course_fixture()

      payment_fixture(
        course_id: course_a.id,
        status: :successful,
        amount_minor: 1_000,
        paid_at: ~U[2026-05-15 10:00:00Z]
      )

      payment_fixture(
        course_id: course_b.id,
        status: :successful,
        amount_minor: 5_000,
        paid_at: ~U[2026-05-15 10:00:00Z]
      )

      assert [%{revenue_minor: 1_000}] = Analytics.monthly_revenue(course_id: course_a.id)
    end
  end
end
