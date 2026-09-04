defmodule WasomiWeb.AdminLearnerModeTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures

  alias Wasomi.Enrollments
  alias Wasomi.Learning

  defp admin_fixture(attrs \\ %{}) do
    {:ok, admin} = user_fixture(attrs) |> Wasomi.Accounts.update_user_role(:admin)
    admin
  end

  describe "Admin Learner Mode authorization and LiveView flows" do
    setup do
      admin = admin_fixture()
      course = course_fixture(status: :published, price_minor: 50_000)
      module = course_module_fixture(course_id: course.id)
      lecture = lecture_fixture(module_id: module.id, duration_seconds: 100)

      %{admin: admin, course: course, module: module, lecture: lecture}
    end

    test "admin in admin mode is redirected away from learner area to /admin", %{
      conn: conn,
      admin: admin
    } do
      conn = log_in_user(conn, admin)

      assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, ~p"/dashboard")
      assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, ~p"/courses-taken")
    end

    test "admin in learner mode can access learner area and sees Switch to Admin Mode button", %{
      conn: conn,
      admin: admin,
      course: course
    } do
      conn =
        conn
        |> log_in_user(admin)
        |> put_session(:active_mode, "learner")

      {:ok, view, html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#dashboard-starter, #dashboard-stats")
      assert html =~ "Switch to Admin Mode"

      # Also verify catalog, courses-taken, and course detail page
      {:ok, _catalog_view, catalog_html} = live(conn, ~p"/catalog")
      assert catalog_html =~ "Explore all GS1 courses."
      assert catalog_html =~ "Switch to Admin Mode"

      {:ok, _courses_view, courses_html} = live(conn, ~p"/courses-taken")
      assert courses_html =~ "My courses"

      {:ok, _show_view, show_html} = live(conn, ~p"/courses/#{course.slug}")
      assert show_html =~ "Switch to Admin Mode"
      assert show_html =~ ~p"/catalog"
      refute show_html =~ "Admin dashboard"
    end

    test "admin in learner mode is strictly blocked from accessing /admin routes", %{
      conn: conn,
      admin: admin
    } do
      conn =
        conn
        |> log_in_user(admin)
        |> put_session(:active_mode, "learner")

      assert {:error, {:redirect, %{to: "/dashboard", flash: flash}}} = live(conn, ~p"/admin")
      assert flash["error"] =~ "Administrative actions are unavailable while in Learner Mode"

      assert {:error, {:redirect, %{to: "/dashboard", flash: flash}}} =
               live(conn, ~p"/admin/courses")

      assert flash["error"] =~ "Administrative actions are unavailable while in Learner Mode"
    end

    test "admin in learner mode can enroll internally, access course player, and track progress",
         %{
           conn: conn,
           admin: admin,
           course: course,
           lecture: lecture
         } do
      conn =
        conn
        |> log_in_user(admin)
        |> put_session(:active_mode, "learner")

      refute Enrollments.can_access_course?(admin, course)

      # Visiting checkout instantly activates internal enrollment and redirects into the course player
      assert {:error, {:redirect, %{to: "/learn/courses/" <> _}}} =
               live(conn, ~p"/courses/#{course.slug}/checkout")

      assert Enrollments.can_access_course?(admin, course)

      # Can open course player as a real student
      {:ok, _player_view, html} = live(conn, ~p"/learn/courses/#{course.slug}")
      assert html =~ course.title
      assert html =~ lecture.title

      # Real progress tracking
      assert {:ok, progress, _celebrations} = Learning.record_progress(admin, lecture, 20)
      assert progress.status == :in_progress
      assert progress.last_position_seconds == 20
    end

    test "admin sidebar in admin mode renders Switch to Learner Mode button", %{
      conn: conn,
      admin: admin
    } do
      conn = log_in_user(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ "Switch to Learner Mode"
      assert html =~ "/users/active-mode"
    end
  end
end
