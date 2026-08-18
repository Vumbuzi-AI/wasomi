defmodule Wasomi.Assessments.FlashcardGenerator do
  @moduledoc """
  Boundary for turning course material into draft flashcards.

  `generate_flashcards/2` works from extracted document/transcript text.

  Implementations return already-parsed, shape-checked data — a list of
  `%{front: String.t(), back: String.t()}` maps — never raw model output.
  Callers never parse LLM JSON themselves. Mirrors
  `Wasomi.Assessments.QuestionGenerator`.
  """

  @type draft_card :: %{front: String.t(), back: String.t()}

  @callback generate_flashcards(text :: String.t(), opts :: keyword()) ::
              {:ok, [draft_card()]} | {:error, term()}
end
