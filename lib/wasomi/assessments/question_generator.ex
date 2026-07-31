defmodule Wasomi.Assessments.QuestionGenerator do
  @moduledoc """
  Boundary for turning extracted document text into draft multiple-choice
  questions.

  Implementations return already-parsed, shape-checked data — a list of
  `%{prompt: String.t(), options: [%{label: String.t(), correct: boolean()}]}`
  maps — never raw model output. Callers never parse LLM JSON themselves.
  """

  @type draft_option :: %{label: String.t(), correct: boolean()}
  @type draft_question :: %{prompt: String.t(), options: [draft_option()]}

  @callback generate_questions(text :: String.t(), opts :: keyword()) ::
              {:ok, [draft_question()]} | {:error, term()}
end
