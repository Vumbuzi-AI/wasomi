defmodule Wasomi.Catalog.AnalyticsTest do
  use Wasomi.DataCase

  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.CertificatesFixtures
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

  describe "revenue_by_course/1" do
    test "sums successful payments per course, richest first" do
      rich = course_fixture(title: "Rich Course")
      poor = course_fixture(title: "Poor Course")

      payment_fixture(
        course_id: rich.id,
        status: :successful,
        amount_minor: 1_000,
        paid_at: ~U[2026-05-15 10:00:00Z]
      )

      payment_fixture(
        course_id: rich.id,
        status: :successful,
        amount_minor: 4_000,
        paid_at: ~U[2026-05-20 10:00:00Z]
      )

      payment_fixture(
        course_id: poor.id,
        status: :successful,
        amount_minor: 500,
        paid_at: ~U[2026-05-15 10:00:00Z]
      )

      # A pending payment must never count as revenue.
      payment_fixture(course_id: poor.id, status: :pending)

      assert [
               %{course_id: rich_id, title: "Rich Course", revenue_minor: 5_000},
               %{course_id: poor_id, title: "Poor Course", revenue_minor: 500}
             ] = Analytics.revenue_by_course()

      assert rich_id == rich.id
      assert poor_id == poor.id
    end

    test "a course with no successful payments is omitted" do
      course_fixture()
      assert Analytics.revenue_by_course() == []
    end

    test "respects the from/to date range" do
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
        amount_minor: 9_000,
        paid_at: ~U[2026-07-01 10:00:00Z]
      )

      assert [%{revenue_minor: 1_000}] =
               Analytics.revenue_by_course(from: ~D[2026-05-01], to: ~D[2026-05-31])
    end
  end

  describe "quiz_pass_rate_by_course/1" do
    test "percentage of submissions that passed, keyed by course" do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id)
      quiz = quiz_fixture(%{module: module})

      submission_fixture(quiz, %{passed: true, score_percent: 90})
      submission_fixture(quiz, %{passed: true, score_percent: 85})
      submission_fixture(quiz, %{passed: true, score_percent: 80})
      submission_fixture(quiz, %{passed: false, score_percent: 40})

      assert Analytics.quiz_pass_rate_by_course() == %{course.id => 75}
    end

    test "a course with no submissions is omitted" do
      course_fixture()
      assert Analytics.quiz_pass_rate_by_course() == %{}
    end
  end

  describe "completion_rate_by_course/1" do
    test "averages each course's module completion rates" do
      course = course_fixture()
      module_a = course_module_fixture(course_id: course.id, position: 1)
      module_b = course_module_fixture(course_id: course.id, position: 2)
      lecture_a = lecture_fixture(module_id: module_a.id, duration_seconds: 100)
      lecture_fixture(module_id: module_b.id, duration_seconds: 100)

      # Two active enrollees; both finish module A, neither finishes module B.
      active_enrollment(course)
      active_enrollment(course)

      for _ <- 1..2 do
        lecture_progress_fixture(
          user_id: user_fixture().id,
          lecture_id: lecture_a.id,
          status: :completed,
          completed_at: ~U[2026-06-10 09:00:00Z]
        )
      end

      # Module A rate = 100%, module B rate = 0% -> average 50%.
      assert Analytics.completion_rate_by_course() == %{course.id => 50}
    end

    test "a course with no modules with lectures is omitted" do
      course_fixture()
      assert Analytics.completion_rate_by_course() == %{}
    end
  end

  describe "course_scorecards/1" do
    test "combines enrollment, completion, quiz pass rate, and revenue per course" do
      course = course_fixture(title: "Applied Negotiation")
      active_enrollment(course)

      payment_fixture(
        course_id: course.id,
        status: :successful,
        amount_minor: 5_000,
        paid_at: ~U[2026-06-20 10:00:00Z]
      )

      assert [
               %{
                 title: "Applied Negotiation",
                 enrolled: 1,
                 completion_rate_percent: 0,
                 quiz_pass_rate_percent: 0,
                 revenue_minor: 5_000
               }
             ] = Analytics.course_scorecards(course_id: course.id)
    end

    test "sorts richest-first by revenue" do
      lean = course_fixture(title: "Lean Course")
      rich = course_fixture(title: "Rich Course")

      payment_fixture(course_id: lean.id, status: :successful, amount_minor: 1_000)
      payment_fixture(course_id: rich.id, status: :successful, amount_minor: 9_000)

      # payment_fixture/1 always creates its own throwaway course+enrollment
      # alongside the payment (see test/support/fixtures/payments_fixtures.ex)
      # regardless of the course_id override, so scope down to just the two
      # courses under test rather than assuming an empty `courses` table.
      scorecards =
        Analytics.course_scorecards()
        |> Enum.filter(&(&1.course_id in [lean.id, rich.id]))

      assert [%{title: "Rich Course"}, %{title: "Lean Course"}] = scorecards
    end

    test "includes a course with zero of everything" do
      course = course_fixture(title: "Untouched Course")

      assert [%{title: "Untouched Course", enrolled: 0, revenue_minor: 0}] =
               Analytics.course_scorecards(course_id: course.id)
    end
  end

  describe "funnel/1" do
    test "counts checkout started, paid, active, completed, and certified" do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id)
      lecture = lecture_fixture(module_id: module.id, duration_seconds: 100)

      # Two checkout attempts (one successful, one failed) -> "Checkout started" = 2.
      payment_fixture(course_id: course.id, status: :successful)
      payment_fixture(course_id: course.id, status: :failed)

      enrollment = active_enrollment(course)

      lecture_progress_fixture(
        user_id: enrollment.user_id,
        lecture_id: lecture.id,
        status: :completed,
        completed_at: ~U[2026-06-10 09:00:00Z]
      )

      certificate_fixture(type: :course, course_id: course.id, user_id: enrollment.user_id)

      assert Analytics.funnel(course_id: course.id) == [
               %{step: "Checkout started", count: 2},
               %{step: "Paid", count: 1},
               %{step: "Active", count: 1},
               %{step: "Completed", count: 1},
               %{step: "Certified", count: 1}
             ]
    end

    test "with no activity, every step is zero" do
      course_fixture()

      assert Analytics.funnel() == [
               %{step: "Checkout started", count: 0},
               %{step: "Paid", count: 0},
               %{step: "Active", count: 0},
               %{step: "Completed", count: 0},
               %{step: "Certified", count: 0}
             ]
    end
  end
end
