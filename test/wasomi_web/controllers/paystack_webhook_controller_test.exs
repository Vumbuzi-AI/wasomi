defmodule WasomiWeb.PaystackWebhookControllerTest do
  use WasomiWeb.ConnCase
  use Oban.Testing, repo: Wasomi.Repo

  alias Wasomi.Payments.Workers.ProcessPaystackWebhook

  test "rejects an invalid signature", %{conn: conn} do
    body = Jason.encode!(%{"event" => "charge.success", "data" => %{"reference" => "ref"}})

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-paystack-signature", "bad")
      |> post(~p"/webhooks/paystack", body)

    assert response(conn, 401) == ""
    refute_enqueued(worker: ProcessPaystackWebhook)
  end

  test "authenticates the exact body and enqueues quickly", %{conn: conn} do
    body =
      Jason.encode!(%{
        "event" => "charge.success",
        "data" => %{"reference" => "KBI-WEBHOOK"}
      })

    signature =
      :crypto.mac(:hmac, :sha512, "test_paystack_secret", body)
      |> Base.encode16(case: :lower)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-paystack-signature", signature)
      |> post(~p"/webhooks/paystack", body)

    assert response(conn, 200) == ""

    assert_enqueued(
      worker: ProcessPaystackWebhook,
      args: %{"reference" => "KBI-WEBHOOK"}
    )
  end

  test "duplicate webhook delivery keeps one idempotent job", %{conn: conn} do
    body =
      Jason.encode!(%{
        "event" => "charge.success",
        "data" => %{"reference" => "KBI-REPLAY"}
      })

    signature =
      :crypto.mac(:hmac, :sha512, "test_paystack_secret", body)
      |> Base.encode16(case: :lower)

    request = fn ->
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-paystack-signature", signature)
      |> post(~p"/webhooks/paystack", body)
    end

    assert response(request.(), 200) == ""
    assert response(request.(), 200) == ""

    jobs =
      all_enqueued(
        worker: ProcessPaystackWebhook,
        args: %{"reference" => "KBI-REPLAY"}
      )

    assert length(jobs) == 1
  end
end
