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
        active: true
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

  @doc """
  Generate a lecture quiz, defaulting to a freshly created lecture when none
  is given.
  """
  def lecture_quiz_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    lecture = Map.get_lazy(attrs, :lecture, fn -> Wasomi.CatalogFixtures.lecture_fixture() end)

    {:ok, quiz} =
      attrs
      |> Map.delete(:lecture)
      |> Enum.into(%{title: "some lecture quiz"})
      |> then(&Assessments.create_lecture_quiz(lecture, &1))

    quiz
  end

  @doc """
  Generate a lecture quiz generation record, defaulting to a freshly created
  lecture quiz and user, and a "primary video" resource selection, when none
  are given.
  """
  def lecture_quiz_generation_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    quiz = Map.get_lazy(attrs, :lecture_quiz, fn -> lecture_quiz_fixture() end)
    user = Map.get_lazy(attrs, :user, fn -> Wasomi.AccountsFixtures.user_fixture() end)

    {:ok, generation} =
      attrs
      |> Map.drop([:lecture_quiz, :user])
      |> Enum.into(%{
        difficulty: :mixed,
        question_count_requested: 10,
        resource_selection: ["video"],
        source_label: "Primary video transcript"
      })
      |> then(&Assessments.create_lecture_quiz_generation(quiz, user, &1))

    generation
  end

  @doc """
  Generate a practice question with a valid, single-correct-option set, defaulting to
  a freshly created course module when none is given.
  """
  def practice_question_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    module =
      Map.get_lazy(attrs, :module, fn -> Wasomi.CatalogFixtures.course_module_fixture() end)

    {:ok, question} =
      attrs
      |> Map.delete(:module)
      |> Enum.into(%{
        prompt: "What is 2 + 2? (#{System.unique_integer([:positive])})",
        explanation: "Two pairs make four.",
        status: :published,
        position: 1,
        practice_question_options: [
          %{label: "Option A", correct: true, position: 1},
          %{label: "Option B", correct: false, position: 2},
          %{label: "Option C", correct: false, position: 3},
          %{label: "Option D", correct: false, position: 4}
        ]
      })
      |> then(&Assessments.create_practice_question(module, &1))

    question
  end

  @doc """
  Generate a flashcard set, defaulting to a freshly created course module
  when neither `:module` nor `:lecture` is given.
  """
  def flashcard_set_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {:ok, set} = Assessments.get_or_create_flashcard_set(module_or_lecture_scope(attrs))
    set
  end

  defp module_or_lecture_scope(%{lecture: lecture}), do: lecture

  defp module_or_lecture_scope(attrs),
    do: Map.get_lazy(attrs, :module, fn -> Wasomi.CatalogFixtures.course_module_fixture() end)

  @doc """
  Generate a valid draft flashcard map, in the shape returned by a
  `Wasomi.Assessments.FlashcardGenerator` implementation.
  """
  def draft_flashcard_attrs(overrides \\ %{}) do
    Map.merge(%{front: "What is the capital of France?", back: "Paris."}, overrides)
  end

  @doc """
  Generate a flashcard, defaulting to a freshly created flashcard set when
  none is given. Cards only exist via
  `Assessments.mark_flashcard_set_ready/2` (there's no per-card create) so
  this fixture goes through that path and reads the card back — pass
  distinguishing `:front`/`:back` overrides when creating more than one
  card against the same explicit `:flashcard_set`.
  """
  def flashcard_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    set = Map.get_lazy(attrs, :flashcard_set, fn -> flashcard_set_fixture() end)
    overrides = Map.delete(attrs, :flashcard_set)

    {:ok, _count} = Assessments.mark_flashcard_set_ready(set, [draft_flashcard_attrs(overrides)])

    set
    |> Assessments.list_flashcards()
    |> List.last()
  end

  @doc """
  Generate a practice set, defaulting to a freshly created course module
  when neither `:module` nor `:lecture` is given.
  """
  def practice_set_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {:ok, quiz} = Assessments.get_or_create_practice_set(module_or_lecture_scope(attrs))
    quiz
  end

  @doc """
  Generate a practice question, defaulting to a freshly created practice
  quiz when none is given. Mirrors `flashcard_fixture/1`'s reasoning:
  questions only exist via `Assessments.mark_practice_set_ready/2`, so
  this fixture goes through that path and reads the question back.
  """
  def practice_set_question_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    quiz = Map.get_lazy(attrs, :practice_set, fn -> practice_set_fixture() end)
    overrides = Map.delete(attrs, :practice_set)

    {:ok, _count} = Assessments.mark_practice_set_ready(quiz, [draft_question_attrs(overrides)])

    quiz
    |> Assessments.list_practice_set_questions()
    |> List.last()
  end
end
