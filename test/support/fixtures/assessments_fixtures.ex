defmodule Wasomi.AssessmentsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Wasomi.Assessments` context.
  """

  alias Wasomi.Assessments

  @doc """
  Generate a quiz, defaulting to a freshly created course module when none is
  given (each fresh module has its own new course, so quizzes never collide
  on the one-quiz-per-module unique constraint by accident).
  """
  def quiz_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    module =
      Map.get_lazy(attrs, :module, fn -> Wasomi.CatalogFixtures.course_module_fixture() end)

    {:ok, quiz} =
      attrs
      |> Map.delete(:module)
      |> Enum.into(%{
        title: "some quiz",
        description: "some description",
        passing_score_percent: 70,
        active: false
      })
      |> then(&Assessments.create_quiz(module, &1))

    quiz
  end

  @doc """
  A valid four-option, single-correct-answer option set.
  """
  def question_options_attrs do
    [
      %{label: "Option A", correct: true, position: 1},
      %{label: "Option B", correct: false, position: 2},
      %{label: "Option C", correct: false, position: 3},
      %{label: "Option D", correct: false, position: 4}
    ]
  end

  @doc """
  Generate a question with a valid, single-correct-option set, defaulting to
  a freshly created quiz when none is given.
  """
  def question_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    quiz = Map.get_lazy(attrs, :quiz, fn -> quiz_fixture() end)

    {:ok, question} =
      attrs
      |> Map.delete(:quiz)
      |> Enum.into(%{
        prompt: "What is 2 + 2? (#{System.unique_integer([:positive])})",
        explanation: "Two pairs make four.",
        status: :published,
        position: 1,
        question_options: question_options_attrs()
      })
      |> then(&Assessments.create_question(quiz, &1))

    question
  end

  @doc """
  Generate a valid draft question map, in the shape returned by a
  `Wasomi.Assessments.QuestionGenerator` implementation.
  """
  def draft_question_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        prompt: "What is the main idea of section 1?",
        options: [
          %{label: "Correct answer", correct: true},
          %{label: "Distractor A", correct: false},
          %{label: "Distractor B", correct: false},
          %{label: "Distractor C", correct: false}
        ]
      },
      overrides
    )
  end

  @doc """
  Generate a quiz generation record, defaulting to a freshly created quiz and
  user when none are given.
  """
  def quiz_generation_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    quiz = Map.get_lazy(attrs, :quiz, fn -> quiz_fixture() end)
    user = Map.get_lazy(attrs, :user, fn -> Wasomi.AccountsFixtures.user_fixture() end)
    source_filename = Map.get(attrs, :source_filename, "training-manual.pdf")

    {:ok, generation} = Assessments.create_generation(quiz, user, source_filename)
    generation
  end
end
