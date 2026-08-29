defmodule WasomiWeb.ReceiptController do
  use WasomiWeb, :controller

  alias Wasomi.Receipts

  def download(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Receipts.get_for_user(user, id) do
      nil ->
        conn |> put_status(:not_found) |> text("Receipt not found")

      payment ->
        case Receipts.pdf_for(user, id) do
          {:ok, pdf} ->
            conn
            |> put_resp_content_type("application/pdf")
            |> put_resp_header(
              "content-disposition",
              ~s(attachment; filename="#{Receipts.filename(payment)}")
            )
            |> send_resp(200, pdf)

          {:error, _reason} ->
            send_resp(conn, :service_unavailable, "Receipt unavailable")
        end
    end
  end
end
