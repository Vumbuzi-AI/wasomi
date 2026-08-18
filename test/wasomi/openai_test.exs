defmodule Wasomi.OpenAITest do
  use ExUnit.Case, async: true

  alias Wasomi.OpenAI

  setup do
    previous_options = Application.get_env(:wasomi, :openai_check_req_options)
    previous_key = Application.get_env(:wasomi, :openai_api_key)
    previous_model = Application.get_env(:wasomi, :openai_model)

    Application.put_env(:wasomi, :openai_api_key, "test_openai_key")
    Application.put_env(:wasomi, :openai_model, "gpt-5.4-mini")

    Application.put_env(:wasomi, :openai_check_req_options,
      plug: {Req.Test, OpenAI},
      retry: false
    )

    on_exit(fn ->
      if previous_options do
        Application.put_env(:wasomi, :openai_check_req_options, previous_options)
      else
        Application.delete_env(:wasomi, :openai_check_req_options)
      end

      restore_env(:openai_api_key, previous_key)
      restore_env(:openai_model, previous_model)
    end)

    :ok
  end

  test "check/0 validates the key against the configured model" do
    Req.Test.stub(OpenAI, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/models/gpt-5.4-mini"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test_openai_key"]
      Req.Test.json(conn, %{id: "gpt-5.4-mini", object: "model"})
    end)

    assert {:ok, %{authenticated: true, model: "gpt-5.4-mini"}} = OpenAI.check()
  end

  test "probe/0 makes a minimal Responses API call" do
    Req.Test.stub(OpenAI, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/responses"
      Req.Test.json(conn, %{id: "resp_test", model: "gpt-5.4-mini", status: "completed"})
    end)

    assert {:ok,
            %{
              authenticated: true,
              request_id: "resp_test",
              model: "gpt-5.4-mini",
              status: "completed"
            }} = OpenAI.probe()
  end

  test "returns a useful authentication error without exposing the key" do
    Req.Test.stub(OpenAI, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{
        error: %{message: "Incorrect API key provided", type: "invalid_request_error"}
      })
    end)

    assert {:error,
            {:openai, 401,
             %{
               "message" => "Incorrect API key provided",
               "type" => "invalid_request_error"
             }}} = OpenAI.check()
  end

  defp restore_env(key, nil), do: Application.delete_env(:wasomi, key)
  defp restore_env(key, value), do: Application.put_env(:wasomi, key, value)
end
