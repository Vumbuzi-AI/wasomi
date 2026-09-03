defmodule WasomiWeb.AdminLive.CourseShowTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures

  alias Wasomi.Enrollments
  alias Wasomi.Payments

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

      view |> element("button", "Grant access") |> render_click()

      assert has_element?(view, "#grant-access-modal", "Grant access to GS1 Basics")
      assert has_element?(view, "#grant-access-modal", grantable.email)
      refute has_element?(view, "#grant-access-modal", already_enrolled.email)
    end

    test "grants selected learners access, records audit, and notifies them", %{conn: conn} do
      admin = admin_fixture(%{name: "Admin Sean"})
      conn = log_in_user(conn, admin)
      learner = user_fixture(%{name: "Manual Learner"})
      other_learner = user_fixture(%{name: "Second Learner"})
      course = course_fixture(title: "Applied Negotiation", status: :published)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}?tab=students")

      view |> element("button", "Grant access") |> render_click()

      html =
        view
        |> form("#grant-access-form",
          learner_ids: [learner.id, other_learner.id],
          grant_access_form: %{
            reason: "Manual enrollment for a partner scholarship"
          }
        )
        |> render_submit()

      refute has_element?(view, "#grant-access-modal")
      assert html =~ "Access granted to 2 learners"
      assert html =~ "Manual Learner"
      assert html =~ "Second Learner"
      assert Enrollments.can_access_course?(learner, course)
      assert Enrollments.can_access_course?(other_learner, course)

      enrollment = Enrollments.active_enrollment(learner, course)
      assert [audit] = Enrollments.list_audits_for_enrollment(enrollment.id)
      assert audit.admin_user_id == admin.id

      other_enrollment = Enrollments.active_enrollment(other_learner, course)
      assert [other_audit] = Enrollments.list_audits_for_enrollment(other_enrollment.id)
      assert other_audit.admin_user_id == admin.id

      assert_email_sent(subject: "You now have access to Applied Negotiation")
      assert_email_sent(subject: "You now have access to Applied Negotiation")
    end

    test "keeps the modal open for validation errors", %{conn: conn} do
      learner = user_fixture()
      course = course_fixture(status: :published)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}?tab=students")

      view |> element("button", "Grant access") |> render_click()

      html =
        view
        |> form("#grant-access-form",
          learner_ids: [learner.id],
          grant_access_form: %{reason: "too short"}
        )
        |> render_submit()

      assert has_element?(view, "#grant-access-modal")
      assert html =~ "should be at least 10 character"
      refute Enrollments.can_access_course?(learner, course)
    end

    test "disables adding learners until a course is public or internal", %{conn: conn} do
      course = course_fixture(status: :draft)
      _learner = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}?tab=students")

      assert has_element?(view, "button[disabled]", "Grant access")
    end

    test "allows granting access to a draft internal course", %{conn: conn} do
      learner = user_fixture(%{name: "Internal Learner"})
      course = course_fixture(title: "Staff Onboarding", status: :draft, is_internal: true)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}?tab=students")

      refute has_element?(view, "button[disabled]", "Grant access")

      view |> element("button", "Grant access") |> render_click()

      html =
        view
        |> form("#grant-access-form",
          learner_ids: [learner.id],
          grant_access_form: %{
            reason: "Internal staff onboarding cohort"
          }
        )
        |> render_submit()

      assert html =~ "Access granted"
      assert html =~ "Internal Learner"
      assert Enrollments.can_access_course?(learner, course)
    end
  end

  describe "revenue metrics visibility" do
    test "hides revenue to date indicator and revenue stat card for free courses", %{conn: conn} do
      course = course_fixture(is_free: true, status: :published)

      {:ok, _view, html} = live(conn, ~p"/admin/courses/#{course.slug}")

      refute html =~ "Revenue to date"
      refute html =~ ">Revenue</dt>"
      assert html =~ "Free"
      assert html =~ "Students"
      assert html =~ "Modules"
      assert html =~ "Lectures"
    end

    test "renders revenue to date indicator and revenue stat card for paid courses", %{conn: conn} do
      course = course_fixture(is_free: false, price_minor: 50_000, status: :published)

      {:ok, _view, html} = live(conn, ~p"/admin/courses/#{course.slug}")

      assert html =~ "Revenue to date"
      assert html =~ "500 KES"
      assert html =~ "Students"
      assert html =~ "Modules"
      assert html =~ "Lectures"
    end
  end

  describe "course-filtered analytics tab" do
    test "renders analytics panel with funnel, module performance, and video dropoff for paid course",
         %{conn: conn} do
      course = course_fixture(title: "Strategic Management", is_free: false, status: :published)
      module = course_module_fixture(course_id: course.id, title: "Module 1: Foundations")
      lecture = lecture_fixture(module_id: module.id, title: "Lecture 1.1", duration_seconds: 200)
      enrollment = enrollment_fixture(course_id: course.id, status: :active)

      {:ok, _payment} =
        Payments.create_payment(%{
          user_id: enrollment.user_id,
          course_id: course.id,
          enrollment_id: enrollment.id,
          provider: :paystack,
          provider_reference: "ref-#{System.unique_integer([:positive])}",
          amount_minor: 10_000,
          currency: "KES",
          status: :successful,
          paid_at: ~U[2026-06-20 10:00:00Z],
          raw_payload: %{}
        })

      Wasomi.LearningFixtures.lecture_progress_fixture(
        user_id: enrollment.user_id,
        lecture_id: lecture.id,
        status: :in_progress,
        last_position_seconds: 80
      )

      {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.slug}?tab=analytics")

      assert has_element?(view, "#analytics-panel")
      assert html =~ "Course analytics"
      assert html =~ "Conversion funnel"
      assert html =~ "Checkout started"
      assert html =~ "Module 1: Foundations"
      assert html =~ "Completion &amp; Quiz score"
      assert html =~ "Learner retention"
      assert html =~ "Video watch drop-off"
      assert html =~ "Monthly course revenue"
      assert html =~ "Open in full Analytics explorer"

      # Also test switching tabs via LiveView patch
      view |> element("#curriculum-tab") |> render_click()
      assert has_element?(view, "#curriculum-panel")
      refute has_element?(view, "#analytics-panel")

      view |> element("#analytics-tab") |> render_click()
      assert has_element?(view, "#analytics-panel")
    end

    test "omits monthly course revenue section for free courses in analytics tab", %{conn: conn} do
      course = course_fixture(title: "Free Workshop", is_free: true, status: :published)
      module = course_module_fixture(course_id: course.id, title: "Overview Module")
      _lecture = lecture_fixture(module_id: module.id, duration_seconds: 120)
      _enrollment = enrollment_fixture(course_id: course.id, status: :active)

      {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.slug}?tab=analytics")

      assert has_element?(view, "#analytics-panel")
      assert html =~ "Course analytics"
      assert html =~ "Conversion funnel"
      assert html =~ "Overview Module"
      refute html =~ "Monthly course revenue"
    end
  end
end
