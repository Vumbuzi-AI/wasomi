defmodule Wasomi.PostalTest do
  use ExUnit.Case, async: false

  import Swoosh.Email

  alias Wasomi.Postal

  setup do
    previous_config = Application.get_env(:wasomi, Postal)

    Application.put_env(:wasomi, Postal,
      api_url: "https://postal.test/send/message",
      api_key: "postal_test_key",
      from: "no-reply@gs1kenya.org",
      from_name: "Wasomi",
      req_options: [plug: {Req.Test, Postal}, retry: false]
    )

    on_exit(fn ->
      if previous_config do
        Application.put_env(:wasomi, Postal, previous_config)
      else
        Application.delete_env(:wasomi, Postal)
      end
    end)

    :ok
  end

  test "delivers a Swoosh email through the Postal API payload" do
    Req.Test.stub(Postal, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert conn.method == "POST"
      assert conn.request_path == "/send/message"
      assert Plug.Conn.get_req_header(conn, "x-server-api-key") == ["postal_test_key"]
      assert payload["from"] == "Wasomi <no-reply@gs1kenya.org>"
      assert payload["to"] == ["Learner <learner@example.com>"]
      assert payload["subject"] == "Welcome"
      assert payload["plain_body"] == "Hello"
      assert payload["html_body"] == "<p>Hello</p>"

      assert [
               %{
                 "name" => "receipt.pdf",
                 "content_type" => "application/pdf",
                 "data" => "JVBERi0xLjQ="
               }
             ] = payload["attachments"]

      Req.Test.json(conn, %{"status" => "ok"})
    end)

    email =
      new()
      |> to({"Learner", "learner@example.com"})
      |> from({"Wasomi", "contact@example.com"})
      |> subject("Welcome")
      |> text_body("Hello")
      |> html_body("<p>Hello</p>")
      |> attachment(
        Swoosh.Attachment.new({:data, "%PDF-1.4"},
          filename: "receipt.pdf",
          content_type: "application/pdf"
        )
      )

    assert {:ok, %{body: %{"status" => "ok"}}} = Postal.deliver(email)
  end

  test "returns a config error when the API key is missing" do
    Application.put_env(:wasomi, Postal, api_key: nil)

    email =
      new()
      |> to("learner@example.com")
      |> subject("Welcome")
      |> text_body("Hello")

    assert {:error, {:missing_config, :api_key}} = Postal.deliver(email)
  end
end
