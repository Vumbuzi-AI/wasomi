defmodule WasomiWeb.AdminLive.PaymentsTest do
  use WasomiWeb.ConnCase

  import Mox
  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.PaymentsFixtures

  alias Wasomi.{Enrollments, Payments}

  setup :verify_on_exit!

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  defp success_payload(payment) do
    %{
      "id" => 123,
      "reference" => payment.provider_reference,
      "status" => "success",
      "amount" => payment.amount_minor,
      "currency" => payment.currency,
      "paid_at" => "2026-06-25T12:00:00Z",
      "gateway_response" => "Approved"
    }
  end

  test "shows Reconcile only for pending payments", %{conn: conn} do
    pending = payment_fixture(status: :pending)
    successful = payment_fixture(status: :successful)

    {:ok, view, _html} = live(conn, ~p"/admin/payments")

    assert has_element?(
             view,
             ~s{button[phx-value-id="#{pending.id}"]},
             "Reconcile"
           )

    refute has_element?(view, ~s{button[phx-value-id="#{successful.id}"]})
  end

  test "reconciling a pending payment against a live provider success activates the enrollment",
       %{conn: conn} do
    payment = payment_fixture(status: :pending)
    enrollment = Wasomi.Enrollments.get_enrollment!(payment.enrollment_id)

    expect(Wasomi.Payments.ProviderMock, :verify, fn reference ->
      assert reference == payment.provider_reference
      {:ok, success_payload(payment)}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/payments")

    html =
      view
      |> element(~s{button[phx-value-id="#{payment.id}"]}, "Reconcile")
      |> render_click()

    assert html =~ "Payment verified as successful"
    assert html =~ "Approved"
    refute has_element?(view, ~s{button[phx-value-id="#{payment.id}"]})

    assert Payments.get_payment!(payment.id).status == :successful
    assert Enrollments.get_enrollment!(enrollment.id).status == :active
  end

  test "reconciling against a provider decline surfaces the reason and keeps access revoked",
       %{conn: conn} do
    payment = payment_fixture(status: :pending)

    expect(Wasomi.Payments.ProviderMock, :verify, fn _reference ->
      {:ok,
       success_payload(payment)
       |> Map.put("status", "failed")
       |> Map.put("gateway_response", "Insufficient Funds")}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/payments")

    html =
      view
      |> element(~s{button[phx-value-id="#{payment.id}"]}, "Reconcile")
      |> render_click()

    assert html =~ "not successful"
    assert html =~ "Insufficient Funds"
    assert Payments.get_payment!(payment.id).status == :failed
  end
end
