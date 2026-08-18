defmodule Wasomi.Assessments.SmartTestGenerator do
  @moduledoc """
  Boundary for turning course material into a learner-configured timed test.

  Distinct from `Wasomi.Assessments.QuestionGenerator` (which only produces
  multiple-choice questions, in counts it picks itself from how much material
  there is) because a Smart Test is built to the learner's own spec: an exact
  number of multiple-choice questions, an exact number of short-answer
  questions, and a 1–5 difficulty dial.

  Implementations return already-parsed, shape-checked data — never raw model
  output. Callers never parse LLM JSON themselves.
  """

  @type draft_option :: %{label: String.t(), correct: boolean()}

  @typedoc """
  A generated question. `:multiple_choice` carries `options` and no
  `expected_answer`; `:short_answer` carries an `expected_answer` (the model
  answer a learner's free text is scored against) and no options.
  """
  @type draft_question :: %{
          kind: :multiple_choice | :short_answer,
          prompt: String.t(),
          options: [draft_option()],
          expected_answer: String.t() | nil,
          explanation: String.t() | nil
        }

  @doc """
  Options:

    * `:multiple_choice_count` — exact number of multiple-choice questions
    * `:short_answer_count` — exact number of short-answer questions
    * `:difficulty` — 1 (easiest) to 5 (hardest)
  """
  @callback generate_test(text :: String.t(), opts :: keyword()) ::
              {:ok, [draft_question()]} | {:error, term()}
end
