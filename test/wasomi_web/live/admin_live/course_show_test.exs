defmodule WasomiWeb.AdminLive.CourseShowTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures

  alias Wasomi.Enrollments

  defp admin_fixture(attrs) do
    user = user_fixture(attrs)
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture(%{name: "Course Admin"}))}
  end

  describe "course access" do
    test "opens a course-level grant access modal with learners who do not already have access",
         %{conn: conn} do
      course = course_fixture(title: "GS1 Basics", status: :published)
      already_enrolled = user_fixture(%{name: "Enrolled Learner"})
      grantable = user_fixture(%{name: "Grantable Learner"})
      enrollment_fixture(user_id: already_enrolled.id, course_id: course.id, status: :active)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}?tab=students")

      assert has_element?(view, "#students-panel", "Course access")

      view |> element("button", "Add learner") |> render_click()

      assert has_element?(view, "#grant-access-modal", "Grant access to GS1 Basics")
      assert has_element?(view, "#grant-access-modal option", grantable.email)
      refute has_element?(view, "#grant-access-modal option", already_enrolled.email)
    end

    test "grants the selected learner access, records audit, and notifies them", %{conn: conn} do
      admin = admin_fixture(%{name: "Admin Sean"})
      conn = log_in_user(conn, admin)
      learner = user_fixture(%{name: "Manual Learner"})
      course = course_fixture(title: "Applied Negotiation", status: :published)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}?tab=students")

      view |> element("button", "Add learner") |> render_click()

      html =
        view
        |> form("#grant-access-form",
          learner_id: learner.id,
          grant_access_form: %{
            reason: "Manual enrollment for a partner scholarship"
          }
        )
        |> render_submit()

      refute has_element?(view, "#grant-access-modal")
      assert html =~ "Access granted"
      assert html =~ "Manual Learner"
      assert Enrollments.can_access_course?(learner, course)

      enrollment = Enrollments.active_enrollment(learner, course)
      assert [audit] = Enrollments.list_audits_for_enrollment(enrollment.id)
      assert audit.admin_user_id == admin.id
      assert_email_sent(subject: "You now have access to Applied Negotiation")
    end

    test "keeps the modal open for validation errors", %{conn: conn} do
      learner = user_fixture()
      course = course_fixture(status: :published)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}?tab=students")

      view |> element("button", "Add learner") |> render_click()

      html =
        view
        |> form("#grant-access-form",
          learner_id: learner.id,
          grant_access_form: %{reason: "too short"}
        )
        |> render_submit()

      assert has_element?(view, "#grant-access-modal")
      assert html =~ "should be at least 10 character"
      refute Enrollments.can_access_course?(learner, course)
    end

    test "disables adding learners until the course is published", %{conn: conn} do
      course = course_fixture(status: :draft)
      _learner = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}?tab=students")

      assert has_element?(view, "button[disabled]", "Add learner")
    end
  end
end
