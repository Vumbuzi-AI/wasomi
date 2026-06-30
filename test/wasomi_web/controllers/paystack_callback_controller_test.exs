defmodule WasomiWeb.PaystackCallbackControllerTest do
  use WasomiWeb.ConnCase

  import Mox
  import Wasomi.CatalogFixtures

  alias Wasomi.{Enrollments, Payments}

  setup :verify_on_exit!
  setup :register_and_log_in_user

  test "query parameters alone can never activate enrollment", %{conn: conn, user: user} do
    course = course_fixture(status: :published, price_minor: 80_000)
    {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)

    expect(Wasomi.Payments.ProviderMock, :verify, fn _reference ->
      {:error, :provider_unavailable}
    end)

    conn =
      get(
        conn,
        ~p"/payments/paystack/callback?reference=#{payment.provider_reference}&status=success"
      )

    assert redirected_to(conn) ==
             ~p"/courses/#{course.slug}/checkout?status=waiting"

    refute Enrollments.can_access_course?(user, course)
  end
end
