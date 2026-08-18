defmodule Wasomi.Assessments.FlashcardGenerator.OpenAI do
  @moduledoc """
  Generates draft flashcards from source text using the OpenAI Chat
  Completions API, constrained to a JSON schema via `response_format` so
  the response shape is guaranteed by the API rather than hopefully parsed
  from free-form text. Mirrors
  `Wasomi.Assessments.QuestionGenerator.OpenAI`'s structure exactly.
  """

  @behaviour Wasomi.Assessments.FlashcardGenerator

  @api_url "https://api.openai.com/v1/chat/completions"
  @default_model "gpt-5.4-mini"

  # See `QuestionGenerator.OpenAI` for why this is capped rather than chunked.
  @max_source_chars 200_000

  @schema %{
    "type" => "object",
    "properties" => %{
      "cards" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "front" => %{"type" => "string"},
            "back" => %{"type" => "string"}
          },
          "required" => ["front", "back"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["cards"],
    "additionalProperties" => false
  }

  @impl true
  def generate_flashcards(text, opts \\ []) when is_binary(text) do
    min_count = Keyword.get(opts, :min_count, 10)
    max_count = Keyword.get(opts, :max_count, 30)

    request_cards(system_prompt(), user_prompt(text, min_count, max_count))
  end

  defp request_cards(system_prompt, user_prompt) do
    body = %{
      "model" => model(),
      "messages" => [
        %{"role" => "system", "content" => system_prompt},
        %{"role" => "user", "content" => user_prompt}
      ],
      "response_format" => %{
        "type" => "json_schema",
        "json_schema" => %{"name" => "flashcards", "strict" => true, "schema" => @schema}
      }
    }

    with {:ok, response} <- request(body) do
      handle_response(response)
    end
  end

  defp system_prompt do
    """
    You are a subject-matter expert in the material covered by the document
    below, with years of experience designing study aids for professional
    training programs. You know how to distill dense material into flashcards
    that reinforce genuine understanding rather than trivia: each card asks
    about one clear, self-contained idea, and its answer is fully supported
    by the document — never something a learner would need to guess at or
    that depends on context the card itself doesn't provide.
    """
  end

  defp user_prompt(text, min_count, max_count) do
    source = String.slice(text, 0, @max_source_chars)

    """
    Generate between #{min_count} and #{max_count} flashcards that help a
    learner recall and understand the key ideas in the document below. Use
    your own judgment on where in that range to land, based on how many
    distinct, well-supported points the document actually contains — do not
    pad with low-value or repetitive cards just to reach the top of the
    range, and do not skip well-supported topics just to stay near the
    bottom of it.

    Before writing cards, identify the document's distinct sections or
    topics. Then allocate cards across them so every identified topic gets
    at least one card before any topic gets a second — do not draw more
    than one or two cards from the same paragraph or idea while other
    topics go untouched.

    Card format:
    - The front is a short, specific question or term/prompt (a question,
      not a fill-in-the-blank sentence fragment).
    - The back is a concise, complete answer — a sentence or short
      paragraph, not a single word unless a single word genuinely is the
      whole answer.
    - Never invent facts not present in the document, and never write a
      card whose answer requires general knowledge the document doesn't
      supply.

    Document:
    ---
    #{source}
    ---
    """
  end

  defp handle_response(%{"choices" => [%{"message" => %{"content" => json}} | _]}) do
    parse_flashcards(json)
  end

  defp handle_response(%{"choices" => []}), do: {:error, :no_completion_returned}
  defp handle_response(body), do: {:error, {:unexpected_response, body}}

  defp parse_flashcards(json) do
    case Jason.decode(strip_code_fence(json)) do
      {:ok, %{"cards" => cards}} when is_list(cards) ->
        {:ok, Enum.map(cards, &normalize_card/1)}

      {:ok, other} ->
        {:error, {:unexpected_shape, other}}

      {:error, reason} ->
        {:error, {:invalid_json, reason}}
    end
  end

  defp strip_code_fence(content) do
    content
    |> String.trim()
    |> String.replace(~r/\A```json\s*/i, "")
    |> String.replace(~r/\A```\s*/i, "")
    |> String.replace(~r/\s*```\z/, "")
    |> String.trim()
  end

  defp normalize_card(%{"front" => front, "back" => back}), do: %{front: front, back: back}
  defp normalize_card(other), do: %{front: nil, back: nil, raw: other}

  defp request(body) do
    with {:ok, api_key} <- api_key() do
      response =
        Req.post(@api_url,
          json: body,
          headers: [
            {"Content-Type", "application/json"},
            {"Authorization", "Bearer #{api_key}"}
          ],
          retry: :transient,
          max_retries: 5,
          receive_timeout: 120_000
        )

      case response do
        {:ok, %{status: 200, body: response_body}} ->
          {:ok, response_body}

        {:ok, %{status: status, body: response_body}} ->
          {:error, {:http_error, status, response_body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp api_key do
    case Application.get_env(:wasomi, :openai_api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :openai_api_key_not_configured}
    end
  end

  defp model, do: Application.get_env(:wasomi, :openai_model, @default_model)
end
