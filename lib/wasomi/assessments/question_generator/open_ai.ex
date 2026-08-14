defmodule Wasomi.Assessments.QuestionGenerator.OpenAI do
  @moduledoc """
  Generates draft multiple-choice questions from source text using the
  OpenAI Chat Completions API, constrained to a JSON schema via
  `response_format` so the response shape is guaranteed by the API rather
  than hopefully parsed from free-form text.

  No official OpenAI SDK exists for Elixir, so this adapter speaks the
  Chat Completions API directly over `Req` — the same HTTP client already
  used for the Paystack and Mux adapters (mirrors the setup in the Medic
  project's `Medic.ArtificialIntelligence.OpenAI`).
  """

  @behaviour Wasomi.Assessments.QuestionGenerator

  @api_url "https://api.openai.com/v1/chat/completions"
  @default_model "gpt-5.4-mini"

  # Larger documents cost more input tokens, slows the response, and — even within
  # the model's real context window — LLMs attend less reliably to content
  # buried mid-prompt ("lost in the middle"). 200k chars (~35-40k words)
  # covers most module-length training documents; longer ones are
  # truncated, since this adapter doesn't chunk across multiple calls.
  @max_source_chars 200_000

  @schema %{
    "type" => "object",
    "properties" => %{
      "questions" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "prompt" => %{"type" => "string"},
            "options" => %{
              "type" => "array",
              "items" => %{
                "type" => "object",
                "properties" => %{
                  "label" => %{"type" => "string"},
                  "correct" => %{"type" => "boolean"}
                },
                "required" => ["label", "correct"],
                "additionalProperties" => false
              }
            }
          },
          "required" => ["prompt", "options"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["questions"],
    "additionalProperties" => false
  }

  @impl true
  def generate_questions(text, opts \\ []) when is_binary(text) do
    min_count = Keyword.get(opts, :min_count, 8)
    max_count = Keyword.get(opts, :max_count, 20)
    difficulty = Keyword.get(opts, :difficulty)
    avoid_duplicating = Keyword.get(opts, :avoid_duplicating, [])

    body = %{
      "model" => model(),
      "messages" => [
        %{"role" => "system", "content" => system_prompt()},
        %{
          "role" => "user",
          "content" => user_prompt(text, min_count, max_count, difficulty, avoid_duplicating)
        }
      ],
      "response_format" => %{
        "type" => "json_schema",
        "json_schema" => %{"name" => "quiz_questions", "strict" => true, "schema" => @schema}
      }
    }

    with {:ok, response} <- request(body) do
      handle_response(response)
    end
  end

  defp system_prompt do
    """
    You are a subject-matter expert in the material covered by the document
    below, with years of experience designing curricula and assessments for
    professional training programs. You know this material deeply enough to
    write questions with complete confidence in their factual accuracy — but
    your years of teaching have also taught you that a good assessment writer
    never uses that expertise to be clever or obscure. Every question you
    write is clear and unambiguous to a learner who studied the material in
    good faith, testing real understanding rather than trying to trick them
    with wording, edge cases, or trivia the document doesn't actually cover.
    """
  end

  defp user_prompt(text, min_count, max_count, difficulty, avoid_duplicating) do
    source = String.slice(text, 0, @max_source_chars)

    """
    Generate between #{min_count} and #{max_count} quiz questions that test
    understanding of the document below. Use your own judgment on where in
    that range to land, based on how many distinct, well-supported points
    the document actually contains — do not pad with low-value or repetitive
    questions just to reach the top of the range, and do not skip
    well-supported topics just to stay near the bottom of it.

    Before writing questions, identify the document's distinct
    sections or topics. Then allocate questions across them so every
    identified topic gets at least one question before any topic gets a
    second — do not draw more than one or two questions from the same
    paragraph or idea while other topics go untouched.

    Coverage and difficulty:
    #{difficulty_instruction(difficulty)}
    - Never invent facts not present in the document, and never write a
      question that can be answered from general knowledge alone.
    - STRICT REQUIREMENT: Never write meta-questions about the text formatting, headings, lecture titles, line numbers, or document structure (e.g. NEVER ask "Which title appears at the top of the document?", "What is lecture 1 titled?", or "Which phrase appears in lecture 2?"). Write questions ONLY about actual subject-matter concepts, definitions, principles, techniques, and domain knowledge.
    #{seed_questions_instruction(avoid_duplicating)}
    Question format:
    - Most questions should be multiple-choice with exactly four options,
      exactly one marked correct: true and the rest correct: false.
    - Where a concept is a simple factual or definitional statement better
      suited to a true/false check, use exactly two options labeled "True"
      and "False" instead — use this format for roughly one in four
      questions, not more.
    - Avoid options that are trivially eliminated by length, wording style,
      or "all/none of the above" — every option should be a plausible answer
      to someone who has not read the document.

    Document:
    ---
    #{source}
    ---
    """
  end

  defp difficulty_instruction(:easy) do
    "- Keep every question at recall level: key facts, terms, and definitions stated directly in the document."
  end

  defp difficulty_instruction(:hard) do
    "- Favor questions that require connecting or applying multiple concepts from the document, not just recalling a single stated fact."
  end

  defp difficulty_instruction(:medium) do
    "- Favor straightforward comprehension questions over pure recall or multi-step application."
  end

  defp difficulty_instruction(_mixed_or_unset) do
    """
    - Mix difficulty: include some questions that check basic recall of key
      facts, and some that require connecting or applying concepts from the
      document.
    """
  end

  defp seed_questions_instruction([]), do: ""

  defp seed_questions_instruction(prompts) do
    list = Enum.map_join(prompts, "\n", &"- #{&1}")

    """

    This module's individual lectures already have these quiz questions:
    #{list}

    Build on top of that existing coverage rather than re-deriving it —
    write broader, module-level synthesis questions that connect ideas
    across lectures instead of restating any of the above, and never reuse
    one of the above questions verbatim.
    """
  end

  defp handle_response(%{"choices" => [%{"message" => %{"content" => json}} | _]}) do
    parse_questions(json)
  end

  defp handle_response(%{"choices" => []}), do: {:error, :no_completion_returned}
  defp handle_response(body), do: {:error, {:unexpected_response, body}}

  defp parse_questions(json) do
    case Jason.decode(strip_code_fence(json)) do
      {:ok, %{"questions" => questions}} when is_list(questions) ->
        {:ok, Enum.map(questions, &normalize_question/1)}

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

  defp normalize_question(%{"prompt" => prompt, "options" => options}) do
    %{prompt: prompt, options: Enum.map(options, &normalize_option/1)}
  end

  defp normalize_question(other), do: %{prompt: nil, options: [], raw: other}

  defp normalize_option(%{"label" => label, "correct" => correct}),
    do: %{label: label, correct: correct}

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
