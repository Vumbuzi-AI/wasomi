defmodule WasomiWeb.AdminLive.DashboardTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures

  alias Wasomi.Payments

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  test "stat cards reflect real revenue, student, enrollment, and course counts", %{conn: conn} do
    course = course_fixture(status: :published)
    course_fixture(status: :draft)
    enrollment_fixture(user_id: user_fixture().id, course_id: course.id, status: :active)

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

    assert html =~ "Business overview"
    assert html =~ Payments.format_minor(payment.amount_minor)
    assert html =~ "1 successful payments"
    assert html =~ ~r/Courses.*?>\s*2\s*</s
    assert html =~ "1 published"
  end

  test "top courses by revenue lists the highest earners, richest first", %{conn: conn} do
    lean = course_fixture(title: "Lean Course")
    rich = course_fixture(title: "Rich Course")

    Payments.create_payment(%{
      user_id: user_fixture().id,
      course_id: lean.id,
      enrollment_id: enrollment_fixture(course_id: lean.id).id,
      provider: :paystack,
      provider_reference: "ref-#{System.unique_integer([:positive])}",
      amount_minor: 1_000,
      currency: "KES",
      status: :successful,
      paid_at: ~U[2026-06-20 10:00:00Z],
      raw_payload: %{}
    })

    Payments.create_payment(%{
      user_id: user_fixture().id,
      course_id: rich.id,
      enrollment_id: enrollment_fixture(course_id: rich.id).id,
      provider: :paystack,
      provider_reference: "ref-#{System.unique_integer([:positive])}",
      amount_minor: 9_000,
      currency: "KES",
      status: :successful,
      paid_at: ~U[2026-06-20 10:00:00Z],
      raw_payload: %{}
    })

    {:ok, _view, html} = live(conn, ~p"/admin")

    assert html =~ ~r/Rich Course.*Lean Course/s
  end

  test "shows empty states when there is no revenue or courses yet", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin")

    assert html =~ "No courses yet. Create your first course to start selling."
    assert html =~ "Payments will appear here as learners check out."
  end
end
