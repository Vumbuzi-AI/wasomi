defmodule WasomiWeb.PaystackCallbackController do
  use WasomiWeb, :controller

  alias Wasomi.Payments
  alias Wasomi.Repo

  def show(conn, %{"reference" => reference}) do
    case Payments.get_payment_by_reference(reference) do
      %{user_id: user_id} = payment when user_id == conn.assigns.current_user.id ->
        payment = Repo.preload(payment, :course)

        case Payments.process_paystack_reference(reference) do
          {:ok, _result} ->
            redirect(conn, to: ~p"/learn/courses/#{payment.course.slug}")

          {:error, _reason} ->
            conn
            |> put_flash(:error, "We could not confirm that payment yet. We will keep checking.")
            |> redirect(to: ~p"/courses/#{payment.course.slug}/checkout?status=waiting")
        end

      _ ->
        conn
        |> put_status(:not_found)
        |> text("Payment not found")
    end
  end

  def show(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> text("Missing payment reference")
  end
end
