defmodule Wasomi.Assessments.SmartTestGenerator.OpenAI do
  @moduledoc """
  Generates a learner-configured Smart Test from source text using the OpenAI
  Chat Completions API, constrained to a JSON schema via `response_format` so
  the response shape is guaranteed by the API rather than hopefully parsed
  from free-form text. Mirrors
  `Wasomi.Assessments.QuestionGenerator.OpenAI`'s structure exactly.
  """

  @behaviour Wasomi.Assessments.SmartTestGenerator

  @api_url "https://api.openai.com/v1/chat/completions"
  @default_model "gpt-5.4-mini"

  # See `QuestionGenerator.OpenAI` for why this is capped rather than chunked.
  @max_source_chars 200_000

  # `strict` JSON schemas require every property to be listed in `required`,
  # so both kind-specific fields are always present and the kind decides
  # which one carries meaning: `options` is `[]` for short answer, and
  # `expected_answer` is `""` for multiple choice.
  @schema %{
    "type" => "object",
    "properties" => %{
      "questions" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "kind" => %{"type" => "string", "enum" => ["multiple_choice", "short_answer"]},
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
            },
            "expected_answer" => %{"type" => "string"},
            "explanation" => %{"type" => "string"}
          },
          "required" => ["kind", "prompt", "options", "expected_answer", "explanation"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["questions"],
    "additionalProperties" => false
  }

  @impl true
  def generate_test(text, opts \\ []) when is_binary(text) do
    multiple_choice_count = Keyword.get(opts, :multiple_choice_count, 6)
    short_answer_count = Keyword.get(opts, :short_answer_count, 2)
    difficulty = Keyword.get(opts, :difficulty, 3)

    body = %{
      "model" => model(),
      "messages" => [
        %{"role" => "system", "content" => system_prompt()},
        %{
          "role" => "user",
          "content" => user_prompt(text, multiple_choice_count, short_answer_count, difficulty)
        }
      ],
      "response_format" => %{
        "type" => "json_schema",
        "json_schema" => %{"name" => "smart_test", "strict" => true, "schema" => @schema}
      }
    }

    with {:ok, response} <- request(body) do
      handle_response(response)
    end
  end

  defp system_prompt do
    """
    You are a subject-matter expert in the material covered by the document
    below, with years of experience writing timed assessments for
    professional training programs. You know this material deeply enough to
    write questions with complete confidence in their factual accuracy — but
    your years of teaching have also taught you that a good assessment writer
    never uses that expertise to be clever or obscure. Every question you
    write is clear and unambiguous to a learner who studied the material in
    good faith, testing real understanding rather than trying to trick them
    with wording, edge cases, or trivia the document doesn't actually cover.
    """
  end

  defp user_prompt(text, multiple_choice_count, short_answer_count, difficulty) do
    source = String.slice(text, 0, @max_source_chars)

    """
    Write a timed test on the document below, containing EXACTLY:
    - #{multiple_choice_count} questions with "kind": "multiple_choice"
    - #{short_answer_count} questions with "kind": "short_answer"

    Return them in a single "questions" array with every multiple-choice
    question before every short-answer question.

    Before writing anything, identify the document's distinct sections or
    topics. Then allocate questions across them so every identified topic
    gets at least one question before any topic gets a second — do not draw
    more than one question from the same paragraph or idea while other topics
    go untouched.

    Difficulty: #{difficulty} on a 1–5 scale.
    #{difficulty_instruction(difficulty)}

    Multiple-choice questions:
    - Exactly four options, exactly one with "correct": true and the other
      three "correct": false. Leave "expected_answer" as an empty string.
    - Every option must be written specifically for its own question. NEVER
      reuse an option's text across two questions, and never let one
      question's correct answer appear as an option under another question.
    - Every option must be a plausible answer to someone who has not read
      the document: no options that are trivially eliminated by length,
      wording style, or "all/none of the above", and no options that merely
      restate the question, a heading, or a lesson title.
    - Where a concept is a simple factual or definitional statement better
      suited to a true/false check, use exactly two options labeled "True"
      and "False" instead — at most one question in four.

    Short-answer questions:
    - Ask for something a learner can answer in two or three sentences, and
      leave "options" as an empty array.
    - Put a complete model answer in "expected_answer" — the learner's own
      wording is graded against it for meaning, so it must contain every
      point that a full answer needs and nothing that isn't in the document.

    Every question:
    - Put a one or two sentence "explanation" of why the answer is right,
      grounded in the document, so the learner can learn from a wrong answer.
    - Never invent facts not present in the document, and never write a
      question that can be answered from general knowledge alone.
    - STRICT REQUIREMENT: Never write meta-questions about the text formatting, headings, lecture titles, line numbers, or document structure (e.g. NEVER ask "Which title appears at the top of the document?", "What is lecture 1 titled?", or "Which phrase appears in lecture 2?"). Write questions ONLY about actual subject-matter concepts, definitions, principles, techniques, and domain knowledge.

    Document:
    ---
    #{source}
    ---
    """
  end

  defp difficulty_instruction(difficulty) when difficulty <= 1 do
    "- Keep every question at recall level: key facts, terms, and definitions stated directly in the document."
  end

  defp difficulty_instruction(2) do
    "- Mostly recall of stated facts and definitions, with a few straightforward comprehension questions."
  end

  defp difficulty_instruction(3) do
    "- Favor straightforward comprehension questions over pure recall, with a couple that apply a single concept to a simple scenario."
  end

  defp difficulty_instruction(4) do
    "- Favor questions that apply concepts to realistic scenarios, or that require connecting two ideas from different parts of the document."
  end

  defp difficulty_instruction(_five_or_higher) do
    """
    - Make every question demand real synthesis: applying concepts to
      unfamiliar scenarios, comparing approaches, or reasoning through the
      consequences of a change. Still answerable purely from the document —
      hard, never obscure or ambiguous.
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

  defp normalize_question(%{"kind" => "short_answer", "prompt" => prompt} = question) do
    %{
      kind: :short_answer,
      prompt: prompt,
      options: [],
      expected_answer: blank_to_nil(Map.get(question, "expected_answer")),
      explanation: blank_to_nil(Map.get(question, "explanation"))
    }
  end

  defp normalize_question(%{"prompt" => prompt} = question) do
    %{
      kind: :multiple_choice,
      prompt: prompt,
      options: question |> Map.get("options", []) |> Enum.map(&normalize_option/1),
      expected_answer: nil,
      explanation: blank_to_nil(Map.get(question, "explanation"))
    }
  end

  defp normalize_question(other),
    do: %{kind: nil, prompt: nil, options: [], expected_answer: nil, explanation: nil, raw: other}

  defp normalize_option(%{"label" => label, "correct" => correct}),
    do: %{label: label, correct: correct}

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

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
