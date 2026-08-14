defmodule Wasomi.Catalog.LectureQuestionScorer.OpenAITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Wasomi.Catalog.LectureQuestionScorer.OpenAI

  @question "What is photosynthesis?"
  @model_answer "The process by which plants convert light into chemical energy."
  @learner_answer "Plants use sunlight to make food."

  describe "score/3 – successful responses" do
    test "returns {:ok, score} for a valid 200 response" do
      Req.Test.stub(OpenAI, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [
            %{
              "message" => %{
                "content" => Jason.encode!(%{"score" => 0.85})
              }
            }
          ]
        })
      end)

      assert {:ok, 0.85} = OpenAI.score(@question, @model_answer, @learner_answer)
    end

    test "clamps scores above 1.0 to 1.0" do
      Req.Test.stub(OpenAI, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [
            %{"message" => %{"content" => Jason.encode!(%{"score" => 1.5})}}
          ]
        })
      end)

      assert {:ok, 1.0} = OpenAI.score(@question, @model_answer, @learner_answer)
    end

    test "clamps scores below 0.0 to 0.0" do
      Req.Test.stub(OpenAI, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [
            %{"message" => %{"content" => Jason.encode!(%{"score" => -0.3})}}
          ]
        })
      end)

      assert {:ok, 0.0} = OpenAI.score(@question, @model_answer, @learner_answer)
    end
  end

  describe "score/3 – HTTP error responses" do
    test "returns {:error, {:http_error, 401, _}} on unauthorized" do
      Req.Test.stub(OpenAI, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          401,
          Jason.encode!(%{"error" => %{"message" => "Invalid API key"}})
        )
      end)

      log =
        capture_log(fn ->
          assert {:error, {:http_error, 401, body}} =
                   OpenAI.score(@question, @model_answer, @learner_answer)

          assert body["error"]["message"] == "Invalid API key"
        end)

      assert log =~ "OpenAI scorer: HTTP 401"
    end

    test "returns {:error, {:http_error, 429, _}} on rate limit" do
      Req.Test.stub(OpenAI, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          429,
          Jason.encode!(%{"error" => %{"message" => "Rate limit exceeded"}})
        )
      end)

      log =
        capture_log(fn ->
          assert {:error, {:http_error, 429, _body}} =
                   OpenAI.score(@question, @model_answer, @learner_answer)
        end)

      assert log =~ "OpenAI scorer: HTTP 429"
    end

    test "returns {:error, {:http_error, 500, _}} on server error" do
      Req.Test.stub(OpenAI, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          500,
          Jason.encode!(%{"error" => %{"message" => "Internal server error"}})
        )
      end)

      log =
        capture_log(fn ->
          assert {:error, {:http_error, 500, _body}} =
                   OpenAI.score(@question, @model_answer, @learner_answer)
        end)

      assert log =~ "OpenAI scorer: HTTP 500"
    end
  end

  describe "score/3 – malformed API responses" do
    test "returns {:error, :no_completion_returned} when choices is empty" do
      Req.Test.stub(OpenAI, fn conn ->
        Req.Test.json(conn, %{"choices" => []})
      end)

      log =
        capture_log(fn ->
          assert {:error, :no_completion_returned} =
                   OpenAI.score(@question, @model_answer, @learner_answer)
        end)

      assert log =~ "empty choices"
    end

    test "returns {:error, {:unexpected_response, _}} for an unrecognised body shape" do
      Req.Test.stub(OpenAI, fn conn ->
        Req.Test.json(conn, %{"id" => "chatcmpl-xyz", "object" => "chat.completion"})
      end)

      log =
        capture_log(fn ->
          assert {:error, {:unexpected_response, _body}} =
                   OpenAI.score(@question, @model_answer, @learner_answer)
        end)

      assert log =~ "unexpected response body"
    end

    test "returns {:error, {:unexpected_shape, _}} when JSON lacks a score field" do
      Req.Test.stub(OpenAI, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [
            %{"message" => %{"content" => Jason.encode!(%{"rating" => 0.9})}}
          ]
        })
      end)

      log =
        capture_log(fn ->
          assert {:error, {:unexpected_shape, %{"rating" => 0.9}}} =
                   OpenAI.score(@question, @model_answer, @learner_answer)
        end)

      assert log =~ "unexpected JSON shape"
    end

    test "returns {:error, {:invalid_json, _}} when content is not valid JSON" do
      Req.Test.stub(OpenAI, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [
            %{"message" => %{"content" => "this is not json"}}
          ]
        })
      end)

      log =
        capture_log(fn ->
          assert {:error, {:invalid_json, _reason}} =
                   OpenAI.score(@question, @model_answer, @learner_answer)
        end)

      assert log =~ "invalid JSON"
    end
  end

  describe "score/3 – missing API key" do
    test "returns {:error, :openai_api_key_not_configured} when key is nil" do
      original = Application.get_env(:wasomi, :openai_api_key)

      try do
        Application.put_env(:wasomi, :openai_api_key, nil)

        log =
          capture_log(fn ->
            assert {:error, :openai_api_key_not_configured} =
                     OpenAI.score(@question, @model_answer, @learner_answer)
          end)

        assert log =~ "OPENAI_API_KEY is not configured"
      after
        Application.put_env(:wasomi, :openai_api_key, original)
      end
    end

    test "returns {:error, :openai_api_key_not_configured} when key is empty string" do
      original = Application.get_env(:wasomi, :openai_api_key)

      try do
        Application.put_env(:wasomi, :openai_api_key, "")

        log =
          capture_log(fn ->
            assert {:error, :openai_api_key_not_configured} =
                     OpenAI.score(@question, @model_answer, @learner_answer)
          end)

        assert log =~ "OPENAI_API_KEY is not configured"
      after
        Application.put_env(:wasomi, :openai_api_key, original)
      end
    end
  end
end
