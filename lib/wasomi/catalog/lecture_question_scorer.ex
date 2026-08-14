defmodule Wasomi.Catalog.LectureQuestionScorer do
  @moduledoc """
  Behaviour for scoring a learner's free-text answer against the admin-authored
  model answer for a LectureQuestion.

  Returns a similarity score in [0.0, 1.0]:
    - 1.0 — semantically equivalent to the model answer
    - 0.0 — completely unrelated

  Swappable via the `:lecture_question_scorer` config key, same pattern as
  `Wasomi.Assessments.QuestionGenerator` — production points at
  `LectureQuestionScorer.OpenAI`, tests point at
  `Wasomi.LectureQuestionScorerMock`.
  """

  @callback score(
              question :: String.t(),
              model_answer :: String.t(),
              learner_answer :: String.t()
            ) :: {:ok, float()} | {:error, term()}
end
