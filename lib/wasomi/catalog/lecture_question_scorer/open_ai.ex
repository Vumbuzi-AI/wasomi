defmodule Wasomi.Catalog.LectureQuestionScorer.OpenAI do
  @moduledoc """
  LLM-as-judge scorer: asks an OpenAI model to rate how well a learner's
  free-text answer captures the meaning of the admin-authored model answer,
  returning a float in [0.0, 1.0].

  Speaks the Chat Completions API directly over `Req` with `response_format`
  set to a strict JSON schema, so the score field is guaranteed by the API.
  """

  require Logger

  @behaviour Wasomi.Catalog.LectureQuestionScorer

  @api_url "https://api.openai.com/v1/chat/completions"
  @default_model "gpt-4.1-mini"

  @schema %{
    "type" => "object",
    "properties" => %{
      "score" => %{
        "type" => "number",
        "description" => "Similarity score from 0.0 (completely wrong) to 1.0 (perfect match)"
      }
    },
    "required" => ["score"],
    "additionalProperties" => false
  }

  @impl true
  def score(question, model_answer, learner_answer)
      when is_binary(question) and is_binary(model_answer) and is_binary(learner_answer) do
    body = %{
      "model" => model(),
      "messages" => [
        %{"role" => "system", "content" => system_prompt()},
        %{"role" => "user", "content" => user_prompt(question, model_answer, learner_answer)}
      ],
      "response_format" => %{
        "type" => "json_schema",
        "json_schema" => %{"name" => "score_result", "strict" => true, "schema" => @schema}
      }
    }

    with {:ok, response} <- request(body) do
      handle_response(response)
    end
  end

  defp system_prompt do
    """
    You are an expert assessor scoring a learner's free-text answer against a
    model answer for an e-learning course question.

    Score how well the learner's answer captures the key meaning and concepts
    of the model answer, on a scale from 0.0 to 1.0:
      - 1.0: The learner's answer is semantically equivalent — same meaning,
             even if worded differently.
      - 0.7–0.9: The learner captures the main point but is incomplete or
                 slightly imprecise.
      - 0.4–0.6: The learner has partial understanding — some correct elements,
                 some missing or incorrect.
      - 0.1–0.3: Minimal correct content; mostly off-target.
      - 0.0: Completely wrong or irrelevant.

    Be lenient with phrasing and word choice; focus on conceptual accuracy.
    Return exactly one JSON object with a "score" field and nothing else.
    """
  end

  defp user_prompt(question, model_answer, learner_answer) do
    """
    Question: #{question}

    Model answer: #{model_answer}

    Learner's answer: #{learner_answer}
    """
  end

  defp handle_response(%{"choices" => [%{"message" => %{"content" => json}} | _]}) do
    case Jason.decode(json) do
      {:ok, %{"score" => score}} when is_number(score) ->
        {:ok, score |> max(0.0) |> min(1.0)}

      {:ok, other} ->
        Logger.warning("OpenAI scorer: unexpected JSON shape: #{inspect(other)}")
        {:error, {:unexpected_shape, other}}

      {:error, reason} ->
        Logger.warning("OpenAI scorer: invalid JSON in response: #{inspect(reason)}")
        {:error, {:invalid_json, reason}}
    end
  end

  defp handle_response(%{"choices" => []}) do
    Logger.warning("OpenAI scorer: API returned empty choices")
    {:error, :no_completion_returned}
  end

  defp handle_response(body) do
    Logger.warning("OpenAI scorer: unexpected response body: #{inspect(body)}")
    {:error, {:unexpected_response, body}}
  end

  defp request(body) do
    with {:ok, api_key} <- api_key() do
      opts =
        Keyword.merge(
          [
            json: body,
            headers: [
              {"Content-Type", "application/json"},
              {"Authorization", "Bearer #{api_key}"}
            ],
            retry: :transient,
            max_retries: 2,
            receive_timeout: 30_000
          ],
          req_options()
        )

      case Req.post(@api_url, opts) do
        {:ok, %{status: 200, body: response_body}} ->
          {:ok, response_body}

        {:ok, %{status: status, body: response_body}} ->
          Logger.warning("OpenAI scorer: HTTP #{status}: #{inspect(response_body)}")

          {:error, {:http_error, status, response_body}}

        {:error, reason} ->
          Logger.warning("OpenAI scorer: request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp api_key do
    case Application.get_env(:wasomi, :openai_api_key) do
      key when is_binary(key) and key != "" ->
        {:ok, key}

      _ ->
        Logger.warning("OpenAI scorer: OPENAI_API_KEY is not configured")
        {:error, :openai_api_key_not_configured}
    end
  end

  defp model, do: Application.get_env(:wasomi, :openai_model, @default_model)

  defp req_options, do: Application.get_env(:wasomi, :openai_scorer_req_options, [])
end
