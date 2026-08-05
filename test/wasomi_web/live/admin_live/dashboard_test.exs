defmodule WasomiWeb.AdminLive.DashboardTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures
  import Wasomi.LearningFixtures

  alias Wasomi.Assessments.QuizSubmission
  alias Wasomi.Payments
  alias Wasomi.Repo

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
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

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  test "shows analytics charts built from real course activity", %{conn: conn} do
    course = course_fixture(title: "Applied Negotiation")
    module = course_module_fixture(course_id: course.id, title: "Getting started")
    lecture = lecture_fixture(module_id: module.id, duration_seconds: 100)
    quiz = quiz_fixture(module: module, title: "Getting started quiz")

    enrollment_fixture(user_id: user_fixture().id, course_id: course.id, status: :active)

    lecture_progress_fixture(
      lecture_id: lecture.id,
      status: :completed,
      completed_at: ~U[2026-06-10 09:00:00Z]
    )

    submission_fixture(quiz, %{score_percent: 90})

    {:ok, payment} =
      Payments.create_payment(%{
        user_id: user_fixture().id,
        course_id: course.id,
        enrollment_id: enrollment_fixture(course_id: course.id).id,
        provider: :paystack,
        provider_reference: "ref-#{System.unique_integer([:positive])}",
        amount_minor: 5_000,
        currency: "KES",
        status: :successful,
        paid_at: ~U[2026-06-20 10:00:00Z],
        raw_payload: %{}
      })

    {:ok, _view, html} = live(conn, ~p"/admin")

    assert html =~ "Getting started"
    assert html =~ "100%"
    assert html =~ "Getting started quiz"
    assert html =~ "90%"
    assert html =~ Payments.format_minor(payment.amount_minor)
  end

  test "shows empty states when there is no analytics data yet", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin")

    assert html =~ "No modules with lectures yet."
    assert html =~ "No quiz submissions in range."
    assert html =~ "No in-progress viewers in range."
    assert html =~ "No successful payments in range."
  end

  test "filtering by course patches the URL and narrows the charts", %{conn: conn} do
    course_a = course_fixture(title: "Course A")
    module_a = course_module_fixture(course_id: course_a.id, title: "Module A")
    lecture_fixture(module_id: module_a.id)
    enrollment_fixture(user_id: user_fixture().id, course_id: course_a.id, status: :active)

    course_b = course_fixture(title: "Course B")
    module_b = course_module_fixture(course_id: course_b.id, title: "Module B")
    lecture_fixture(module_id: module_b.id)
    enrollment_fixture(user_id: user_fixture().id, course_id: course_b.id, status: :active)

    {:ok, view, _html} = live(conn, ~p"/admin")

    html =
      view
      |> form("#filter-form", %{"filter" => %{"course_id" => to_string(course_a.id)}})
      |> render_change()

    assert_patch(view, ~p"/admin?course_id=#{course_a.id}")
    assert html =~ "Module A"
    refute html =~ "Module B"
  end

  test "clearing filters removes the query params", %{conn: conn} do
    course = course_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin?course_id=#{course.id}")

    view |> element("a", "Clear filters") |> render_click()

    assert_patch(view, ~p"/admin")
  end
end
