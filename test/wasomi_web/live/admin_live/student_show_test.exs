defmodule WasomiWeb.AdminLive.StudentShowTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures

  alias Wasomi.Enrollments

  defp admin_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  test "renders the learner's profile", %{conn: conn} do
    learner = user_fixture(%{name: "Amaya Otieno"})
    {:ok, _view, html} = live(conn, ~p"/admin/students/#{learner.id}")

    assert html =~ "Amaya Otieno"
    assert html =~ learner.email
  end

  describe "Grant access modal" do
    test "only offers courses the learner isn't already actively enrolled in", %{conn: conn} do
      learner = user_fixture()
      already_enrolled = course_fixture(title: "Already enrolled course")
      grantable = course_fixture(title: "Grantable course")
      enrollment_fixture(user_id: learner.id, course_id: already_enrolled.id, status: :active)

      {:ok, view, _html} = live(conn, ~p"/admin/students/#{learner.id}")

      view |> element("button", "Grant access") |> render_click()

      assert has_element?(view, "#grant-access-modal")
      assert has_element?(view, "#grant-access-modal option", grantable.title)
      refute has_element?(view, "#grant-access-modal option", already_enrolled.title)
    end

    test "grants access, records the audit, and notifies the learner", %{conn: conn} do
      admin = user_fixture(%{name: "Admin Sean"})
      {:ok, admin} = Wasomi.Accounts.update_user_role(admin, :admin)
      conn = log_in_user(conn, admin)

      learner = user_fixture()
      course = course_fixture(title: "Applied Negotiation")

      {:ok, view, _html} = live(conn, ~p"/admin/students/#{learner.id}")

      view |> element("button", "Grant access") |> render_click()

      html =
        view
        |> form("#grant-access-form",
          grant_access_form: %{
            course_id: course.id,
            reason: "Manual enrollment for a partner scholarship"
          }
        )
        |> render_submit()

      refute has_element?(view, "#grant-access-modal")
      assert html =~ "Access granted"
      assert html =~ "Applied Negotiation"

      assert Enrollments.can_access_course?(learner, course)

      assert [audit] =
               Enrollments.list_audits_for_enrollment(
                 Enrollments.active_enrollment(learner, course).id
               )

      assert audit.admin_user_id == admin.id
      assert_email_sent(subject: "You now have access to Applied Negotiation")
    end

    test "shows a validation error for a too-short reason and keeps the modal open", %{
      conn: conn
    } do
      learner = user_fixture()
      course = course_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/students/#{learner.id}")

      view |> element("button", "Grant access") |> render_click()

      html =
        view
        |> form("#grant-access-form",
          grant_access_form: %{course_id: course.id, reason: "too short"}
        )
        |> render_submit()

      assert has_element?(view, "#grant-access-modal")
      assert html =~ "should be at least 10 character"
      refute Enrollments.can_access_course?(learner, course)
    end

    test "disables the Grant access button once every course is already active", %{conn: conn} do
      learner = user_fixture()
      course = course_fixture()
      enrollment_fixture(user_id: learner.id, course_id: course.id, status: :active)

      {:ok, view, _html} = live(conn, ~p"/admin/students/#{learner.id}")

      assert has_element?(view, "button[disabled]", "Grant access")
    end
  end
end
