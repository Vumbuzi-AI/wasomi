defmodule WasomiWeb.AdminLive.StudentShowTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures

  alias Wasomi.Enrollments
  alias WasomiWeb.AdminLive.StudentShow

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
      already_enrolled = course_fixture(title: "Already enrolled course", status: :published)
      grantable = course_fixture(title: "Grantable course", status: :published)
      enrollment_fixture(user_id: learner.id, course_id: already_enrolled.id, status: :active)

      {:ok, view, _html} = live(conn, ~p"/admin/students/#{learner.id}")

      view |> element("button", "Grant access") |> render_click()

      assert has_element?(view, "#grant-access-modal")
      assert has_element?(view, "#grant-access-modal option", grantable.title)
      refute has_element?(view, "#grant-access-modal option", already_enrolled.title)
    end

    test "offers draft internal courses because they are grant-only", %{conn: conn} do
      learner = user_fixture()
      internal = course_fixture(title: "Internal onboarding", status: :draft, is_internal: true)
      _draft_public = course_fixture(title: "Unready public course", status: :draft)

      {:ok, view, _html} = live(conn, ~p"/admin/students/#{learner.id}")

      view |> element("button", "Grant access") |> render_click()

      assert has_element?(view, "#grant-access-modal option", internal.title)
      refute has_element?(view, "#grant-access-modal option", "Unready public course")
    end

    test "grants access, records the audit, and notifies the learner", %{conn: conn} do
      admin = user_fixture(%{name: "Admin Sean"})
      {:ok, admin} = Wasomi.Accounts.update_user_role(admin, :admin)
      conn = log_in_user(conn, admin)

      learner = user_fixture()
      course = course_fixture(title: "Applied Negotiation", status: :published)

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
      course = course_fixture(status: :published)

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
      course = course_fixture(status: :published)
      enrollment_fixture(user_id: learner.id, course_id: course.id, status: :active)

      {:ok, view, _html} = live(conn, ~p"/admin/students/#{learner.id}")

      assert has_element?(view, "button[disabled]", "Grant access")
    end

    test "shows a flash instead of crashing when the caller isn't an admin" do
      no_longer_admin = user_fixture()
      learner = user_fixture()
      course = course_fixture()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          user: learner,
          current_user: no_longer_admin,
          grantable_courses: [course],
          modal: :grant_access,
          grant_access_form: nil
        }
      }

      assert {:noreply, socket} =
               StudentShow.handle_event(
                 "grant_access",
                 %{
                   "grant_access_form" => %{
                     "course_id" => course.id,
                     "reason" => "Manual enrollment for a partner scholarship"
                   }
                 },
                 socket
               )

      assert socket.assigns.flash["error"] == "You are not authorized to grant course access."
      refute Enrollments.can_access_course?(learner, course)
    end
  end

  describe "referrals section" do
    test "shows who referred the learner and their referral funnel", %{conn: conn} do
      referrer = user_fixture(%{name: "Jane Referrer"})
      learner = user_fixture(%{name: "Referred Learner"})
      also_referred = user_fixture(%{name: "Downstream Signup"})

      assert {:ok, %Wasomi.Referrals.Referral{}} =
               Wasomi.Referrals.attribute(learner, referrer.referral_code)

      assert {:ok, %Wasomi.Referrals.Referral{}} =
               Wasomi.Referrals.attribute(also_referred, learner.referral_code)

      {:ok, _view, html} = live(conn, ~p"/admin/students/#{learner.id}")

      assert html =~ "Referrals"
      assert html =~ "Jane Referrer"
      assert html =~ "Downstream Signup"

      {:ok, _view, referrer_html} = live(conn, ~p"/admin/students/#{referrer.id}")
      assert referrer_html =~ "Referred Learner"
    end
  end
end
