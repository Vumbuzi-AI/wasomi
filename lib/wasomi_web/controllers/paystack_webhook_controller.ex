defmodule WasomiWeb.PaystackWebhookController do
  use WasomiWeb, :controller

  alias Wasomi.Payments.Workers.ProcessPaystackWebhook

  def create(conn, params) do
    signature = get_req_header(conn, "x-paystack-signature") |> List.first()
    raw_body = conn.private[:raw_body] || ""

    if valid_signature?(raw_body, signature) do
      with reference when is_binary(reference) <- get_in(params, ["data", "reference"]),
           {:ok, _job} <-
             %{"reference" => reference, "event" => params}
             |> ProcessPaystackWebhook.new()
             |> Oban.insert() do
        send_resp(conn, :ok, "")
      else
        _ -> send_resp(conn, :bad_request, "")
      end
    else
      send_resp(conn, :unauthorized, "")
    end
  end

  def valid_signature?(_body, nil), do: false

  def valid_signature?(body, signature) when is_binary(signature) do
    case Application.get_env(:wasomi, :paystack_secret_key) do
      secret when is_binary(secret) and byte_size(secret) > 0 ->
        expected =
          :crypto.mac(:hmac, :sha512, secret, body)
          |> Base.encode16(case: :lower)

        secure_compare(expected, String.downcase(signature))

      _ ->
        false
    end
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_compare(_left, _right), do: false
end
