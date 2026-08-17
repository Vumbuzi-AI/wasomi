defmodule Wasomi.Catalog.OverviewScriptGenerator.OpenAI do
  @moduledoc """
  Turns a lecture's source text into a scene-by-scene video-overview script
  using the OpenAI Chat Completions API, constrained to a JSON schema via
  `response_format` — same approach as
  `Wasomi.Assessments.QuestionGenerator.OpenAI`, including speaking the API
  directly over `Req` rather than an SDK (none exists for Elixir).
  """

  @behaviour Wasomi.Catalog.OverviewScriptGenerator

  @api_url "https://api.openai.com/v1/chat/completions"
  @default_model "gpt-5.4-mini"

  # Same reasoning as QuestionGenerator.OpenAI's @max_source_chars: caps
  # cost/latency and avoids "lost in the middle" attention degradation on
  # long documents. A video overview also needs to stay watchably short, so
  # this is more aggressive than the quiz generator's 200k-char cap.
  @max_source_chars 60_000

  @schema %{
    "type" => "object",
    "properties" => %{
      "scenes" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "narration" => %{"type" => "string"},
            "slide_text" => %{"type" => "string"}
          },
          "required" => ["narration", "slide_text"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["scenes"],
    "additionalProperties" => false
  }

  @impl true
  def generate_script(text, opts \\ []) when is_binary(text) do
    min_scenes = Keyword.get(opts, :min_scenes, 3)
    max_scenes = Keyword.get(opts, :max_scenes, 8)

    body = %{
      "model" => model(),
      "messages" => [
        %{"role" => "system", "content" => system_prompt()},
        %{"role" => "user", "content" => user_prompt(text, min_scenes, max_scenes)}
      ],
      "response_format" => %{
        "type" => "json_schema",
        "json_schema" => %{"name" => "overview_script", "strict" => true, "schema" => @schema}
      }
    }

    with {:ok, response} <- request(body),
         {:ok, scenes} <- handle_response(response) do
      # `max_scenes` above is only a prompt-level ask, not a structural
      # constraint the model is guaranteed to honor (`maxItems` isn't part
      # of OpenAI's supported strict-mode JSON Schema subset for arrays,
      # so it can't be enforced at the schema level either) — a longer
      # source document can plausibly push a model past it, which
      # directly inflates the assembled video's length and generation
      # time. Enforced here instead, unconditionally, regardless of what
      # the model actually returned.
      {:ok, Enum.take(scenes, max_scenes)}
    end
  end

  defp system_prompt do
    """
    You are a curriculum designer who writes scripts for short spoken
    explainer videos that actually teach the material — not a trailer or
    preview of a separate lecture, but a self-contained explanation a
    learner could genuinely learn the concept from on its own. Explain
    ideas clearly, in plain language, with a concrete example wherever the
    source material supports one — don't just name a point, explain it.
    Your narration reads naturally aloud (short sentences, no bullet-point
    phrasing spoken as prose) and never invents facts the source material
    doesn't support.
    """
  end

  defp user_prompt(text, min_scenes, max_scenes) do
    source = String.slice(text, 0, @max_source_chars)

    """
    Write a scene-by-scene script for a short explainer video that teaches
    the material below, between #{min_scenes} and #{max_scenes} scenes. Use
    your own judgment on where in that range to land, based on how many
    distinct points the material actually supports.

    For each scene, provide:
    - "narration": one to three sentences of spoken narration that
      actually explain the point being made, not just name it — written to
      be read aloud by a text-to-speech voice, natural spoken rhythm, no
      markdown, no bullet points spoken as if they were prose.
    - "slide_text": a short on-screen label for that scene (a few words to
      one short phrase, not a restatement of the full narration) — this is
      what appears as text on the slide while the narration plays.

    Order scenes so the video builds understanding step by step, not a
    disconnected list of facts. Never invent facts not present in the
    material below.

    Material:
    ---
    #{source}
    ---
    """
  end

  defp handle_response(%{"choices" => [%{"message" => %{"content" => json}} | _]}) do
    parse_scenes(json)
  end

  defp handle_response(%{"choices" => []}), do: {:error, :no_completion_returned}
  defp handle_response(body), do: {:error, {:unexpected_response, body}}

  defp parse_scenes(json) do
    case Jason.decode(strip_code_fence(json)) do
      {:ok, %{"scenes" => scenes}} when is_list(scenes) ->
        {:ok, Enum.map(scenes, &normalize_scene/1)}

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

  defp normalize_scene(%{"narration" => narration, "slide_text" => slide_text}),
    do: %{narration: narration, slide_text: slide_text}

  defp normalize_scene(other), do: %{narration: nil, slide_text: nil, raw: other}

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
