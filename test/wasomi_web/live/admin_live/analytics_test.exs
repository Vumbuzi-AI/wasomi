defmodule WasomiWeb.AdminLive.AnalyticsTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.CertificatesFixtures
  import Wasomi.EnrollmentsFixtures
  import Wasomi.LearningFixtures

  alias Wasomi.Payments

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  describe "Overview tab (default)" do
    test "shows the conversion funnel and course leaderboard", %{conn: conn} do
      course = course_fixture(title: "Applied Negotiation")
      module = course_module_fixture(course_id: course.id)
      lecture = lecture_fixture(module_id: module.id, duration_seconds: 100)
      enrollment = enrollment_fixture(course_id: course.id, status: :active)

      {:ok, payment} =
        Payments.create_payment(%{
          user_id: enrollment.user_id,
          course_id: course.id,
          enrollment_id: enrollment.id,
          provider: :paystack,
          provider_reference: "ref-#{System.unique_integer([:positive])}",
          amount_minor: 5_000,
          currency: "KES",
          status: :successful,
          paid_at: ~U[2026-06-20 10:00:00Z],
          raw_payload: %{}
        })

      lecture_progress_fixture(
        user_id: enrollment.user_id,
        lecture_id: lecture.id,
        status: :completed,
        completed_at: ~U[2026-06-10 09:00:00Z]
      )

      certificate_fixture(type: :course, course_id: course.id, user_id: enrollment.user_id)

      {:ok, _view, html} = live(conn, ~p"/admin/analytics")

      assert html =~ "Checkout started"
      assert html =~ "Certified"
      assert html =~ "Conversion funnel"
      assert html =~ "Course leaderboard"
      assert html =~ "Applied Negotiation"
      assert html =~ Payments.format_minor(payment.amount_minor)
      assert html =~ "100%"
      assert html =~ "overall, checkout to certificate"
    end

    test "hides the overall-conversion stat instead of showing a hollow 0%", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/analytics")

      assert html =~ "Checkout started"
      refute html =~ "overall, checkout to certificate"
    end

    test "leaderboard paginates when there are more than a page of courses", %{conn: conn} do
      for i <- 1..11 do
        idx = String.pad_leading(Integer.to_string(i), 2, "0")
        course = course_fixture(title: "Leaderboard Course #{idx}")

        Payments.create_payment(%{
          user_id: user_fixture().id,
          course_id: course.id,
          enrollment_id: enrollment_fixture(course_id: course.id).id,
          provider: :paystack,
          provider_reference: "leaderboard-ref-#{idx}",
          amount_minor: i * 1_000,
          currency: "KES",
          status: :successful,
          paid_at: ~U[2026-06-20 10:00:00Z],
          raw_payload: %{}
        })
      end

      {:ok, view, html} = live(conn, ~p"/admin/analytics")

      assert html =~ "Page 1 of 2"
      assert has_element?(view, "table tbody", "Leaderboard Course 11")
      refute has_element?(view, "table tbody", "Leaderboard Course 01")

      view |> element("a", "Next") |> render_click()

      assert_patch(view, ~p"/admin/analytics?page=2")
      assert has_element?(view, "table tbody", "Leaderboard Course 01")
      refute has_element?(view, "table tbody", "Leaderboard Course 11")
    end

    test "filtering by course patches the URL and narrows the leaderboard", %{conn: conn} do
      course_a = course_fixture(title: "Course A")
      _course_b = course_fixture(title: "Course B")

      {:ok, view, _html} = live(conn, ~p"/admin/analytics")

      view
      |> form("#filter-form", %{"filter" => %{"course_id" => to_string(course_a.id)}})
      |> render_change()

      assert_patch(view, ~p"/admin/analytics?course_id=#{course_a.id}")
      assert has_element?(view, "table tbody", "Course A")
      refute has_element?(view, "table tbody", "Course B")
    end
  end

  describe "Revenue tab" do
    test "shows monthly revenue", %{conn: conn} do
      course = course_fixture()

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

      {:ok, view, html} = live(conn, ~p"/admin/analytics")
      refute html =~ "Monthly revenue"

      html = view |> element("button", "Revenue") |> render_click()

      assert html =~ "Monthly revenue"
      assert html =~ Payments.format_minor(payment.amount_minor)
    end

    test "shows an empty state when there is no revenue yet", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/analytics")
      html = view |> element("button", "Revenue") |> render_click()

      assert html =~ "No successful payments in range."
    end
  end

  test "switch_tab ignores an unrecognized tab instead of crashing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/analytics")

    html = render_click(view, "switch_tab", %{"tab" => "not_a_real_tab"})

    assert html =~ "Conversion funnel"
  end

  test "clearing filters removes the query params", %{conn: conn} do
    course = course_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/analytics?course_id=#{course.id}")

    view |> element("a", "Clear filters") |> render_click()

    assert_patch(view, ~p"/admin/analytics")
  end
end
