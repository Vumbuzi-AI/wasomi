defmodule WasomiWeb.CheckoutLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mox
  import Wasomi.CatalogFixtures

  alias Wasomi.Enrollments

  setup :verify_on_exit!
  setup :register_and_log_in_user

  test "renders the hosted checkout handoff", %{conn: conn} do
    course = course_fixture(status: :published, price_minor: 80_000)

    assert {:ok, view, html} = live(conn, ~p"/courses/#{course.slug}/checkout")
    assert html =~ "Enroll &amp; Pay"
    assert has_element?(view, "#pay-with-paystack")
  end

  test "starts Paystack and redirects to its hosted checkout", %{conn: conn} do
    course = course_fixture(status: :published, price_minor: 80_000)

    expect(Wasomi.Payments.ProviderMock, :initiate, fn payment ->
      assert payment.phone == "254712345678"

      {:ok,
       %{
         "authorization_url" => "https://checkout.paystack.test/hosted",
         "access_code" => "access",
         "reference" => payment.provider_reference
       }}
    end)

    {:ok, view, _html} = live(conn, ~p"/courses/#{course.slug}/checkout")

    view
    |> form("#checkout-form", %{"phone" => "0712345678"})
    |> render_submit()

    assert_redirect(view, "https://checkout.paystack.test/hosted")
  end

  test "rejects an invalid M-Pesa number before contacting Paystack", %{conn: conn} do
    course = course_fixture(status: :published, price_minor: 80_000)

    {:ok, view, _html} = live(conn, ~p"/courses/#{course.slug}/checkout")

    html =
      view
      |> form("#checkout-form", %{"phone" => "123"})
      |> render_submit()

    assert html =~ "valid M-Pesa number"
  end

  test "redirects when PubSub confirms this course enrollment", %{conn: conn, user: user} do
    course = course_fixture(status: :published, price_minor: 80_000)
    {:ok, view, _html} = live(conn, ~p"/courses/#{course.slug}/checkout")
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, active} = Enrollments.activate_enrollment(pending)

    send(view.pid, {:payment_confirmed, active})

    assert_redirect(view, ~p"/learn/courses/#{course.slug}")
  end
end
