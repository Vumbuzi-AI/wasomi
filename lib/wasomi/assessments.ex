defmodule Wasomi.Assessments do
  @moduledoc """
  Quiz authoring and scoring.

  A quiz belongs to exactly one course module (one quiz per module — see
  `Wasomi.Assessments.Quiz`). Options are never written independently of
  their parent question: `create_question/2` and `update_question/2` always
  take the question's complete option set, which is what lets "at least one
  correct option" be validated from the submitted attrs alone, with no
  extra database round trip to read sibling rows.

  Draft vs. published questions exist so AI-generated drafts (see the PDF
  ingestion worker) can be reviewed before a learner ever sees them:
  `submit_quiz/2` only scores against `:published` questions.
  """

  import Ecto.Query, warn: false

  alias Wasomi.Accounts.User
  alias Wasomi.Assessments.{Question, Quiz, QuizGeneration, QuizSubmission}
  alias Wasomi.Catalog.CourseModule
  alias Wasomi.Repo

  ## Quizzes

  def get_quiz!(id), do: Repo.get!(Quiz, id)

  @doc """
  Gets the quiz for a module, if one exists. A module has at most one quiz.
  """
  def get_quiz_for_module(%CourseModule{id: module_id}), do: get_quiz_for_module(module_id)

  def get_quiz_for_module(module_id) do
    Repo.get_by(Quiz, module_id: module_id)
  end

  @doc """
  Counts draft (unreviewed) questions for every module in a course, keyed by
  `module_id`. Modules with no quiz, or no drafts, are simply absent from the
  result rather than present with a `0` — callers should use `Map.get/3`.
  """
  def count_draft_questions_by_module(course_id) do
    Question
    |> join(:inner, [q], quiz in Quiz, on: quiz.id == q.quiz_id)
    |> join(:inner, [q, quiz], module in CourseModule, on: module.id == quiz.module_id)
    |> where([q, _quiz, module], module.course_id == ^course_id and q.status == :draft)
    |> group_by([_q, _quiz, module], module.id)
    |> select([q, _quiz, module], {module.id, count(q.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Counts published questions for every module in a course, keyed by
  `module_id`. Mirrors `count_draft_questions_by_module/1`.
  """
  def count_published_questions_by_module(course_id) do
    Question
    |> join(:inner, [q], quiz in Quiz, on: quiz.id == q.quiz_id)
    |> join(:inner, [q, quiz], module in CourseModule, on: module.id == quiz.module_id)
    |> where([q, _quiz, module], module.course_id == ^course_id and q.status == :published)
    |> group_by([_q, _quiz, module], module.id)
    |> select([q, _quiz, module], {module.id, count(q.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Gets every quiz belonging to a course, keyed by `module_id`, so the
  course-curriculum view can show "this module already has a quiz" without
  an N+1 lookup per module.
  """
  def get_quizzes_by_module(course_id) do
    Quiz
    |> join(:inner, [q], module in CourseModule, on: module.id == q.module_id)
    |> where([_q, module], module.course_id == ^course_id)
    |> select([q, module], {module.id, q})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Gets a quiz with every question and option preloaded, any status —
  the admin/authoring view. Learner-facing scoring never uses this; see
  `list_published_questions/1`.
  """
  def get_quiz_with_questions!(id) do
    questions_query = from(question in Question, order_by: [asc: question.position])

    options_query =
      from(option in Wasomi.Assessments.QuestionOption, order_by: [asc: option.position])

    Quiz
    |> Repo.get!(id)
    |> Repo.preload([:module, questions: {questions_query, question_options: options_query}])
  end

  @doc """
  Lists a quiz's `:published` questions with their options, ordered — the
  only question set a learner should ever be scored against.
  """
  def list_published_questions(%Quiz{id: quiz_id}) do
    options_query =
      from(option in Wasomi.Assessments.QuestionOption, order_by: [asc: option.position])

    Question
    |> join(:inner, [question], quiz in Quiz, on: quiz.id == question.quiz_id)
    |> where(
      [question, quiz],
      question.quiz_id == ^quiz_id and question.status == :published and quiz.active == true
    )
    |> order_by([question, _quiz], asc: question.position)
    |> preload([question, _quiz], question_options: ^options_query)
    |> Repo.all()
  end

  def create_quiz(%CourseModule{} = module, attrs) do
    %Quiz{}
    |> Quiz.changeset(Map.put(attrs, :module_id, module.id))
    |> Repo.insert()
  end

  def update_quiz(%Quiz{} = quiz, attrs) do
    quiz
    |> Quiz.changeset(attrs)
    |> Repo.update()
  end

  def delete_quiz(%Quiz{} = quiz), do: Repo.delete(quiz)

  def change_quiz(%Quiz{} = quiz, attrs \\ %{}), do: Quiz.changeset(quiz, attrs)

  ## Questions

  def get_question!(id), do: Repo.get!(Question, id)

  def create_question(%Quiz{} = quiz, attrs) do
    %Question{quiz_id: quiz.id}
    |> Question.changeset(attrs)
    |> Repo.insert()
  end

  def update_question(%Question{} = question, attrs) do
    question
    |> Question.changeset(attrs)
    |> Repo.update()
  end

  def delete_question(%Question{} = question), do: Repo.delete(question)

  def change_question(%Question{} = question, attrs \\ %{}),
    do: Question.changeset(question, attrs)

  @doc """
  Marks a draft question (typically AI-generated) as reviewed and visible
  to learners.
  """
  def publish_question(%Question{} = question) do
    question
    |> Ecto.Changeset.change(status: :published)
    |> Repo.update()
  end

  @doc """
  Reorders every question in a quiz.

  The submitted ids must be the quiz's complete question set. Temporary
  positions avoid violating the unique `(quiz_id, position)` index while
  positions are swapped.
  """
  def reorder_questions(%Quiz{id: quiz_id}, question_ids) when is_list(question_ids) do
    with {:ok, question_ids} <- normalize_ids(question_ids) do
      Repo.transaction(fn ->
        questions =
          Question
          |> where([question], question.quiz_id == ^quiz_id)
          |> order_by([question], asc: question.position)
          |> lock("FOR UPDATE")
          |> Repo.all()

        if Enum.sort(Enum.map(questions, & &1.id)) == Enum.sort(question_ids) do
          persist_question_order(questions, question_ids)
        else
          Repo.rollback(:invalid_order)
        end
      end)
    end
  end

  @doc """
  Publishes a complete quiz atomically.

  A quiz must contain at least one question, every question must have valid
  text and options, and every question must identify a correct option.
  """
  def publish_quiz(%Quiz{id: quiz_id}) do
    Repo.transaction(fn ->
      quiz =
        Quiz
        |> where([quiz], quiz.id == ^quiz_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()
        |> Repo.preload(questions: from(question in Question, preload: :question_options))

      case quiz_completeness_errors(quiz) do
        [] ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          Question
          |> where([question], question.quiz_id == ^quiz.id)
          |> Repo.update_all(set: [status: :published, updated_at: now])

          quiz
          |> Quiz.changeset(%{active: true, published_at: now})
          |> Repo.update!()
          |> Repo.preload([:module, questions: [:question_options]], force: true)

        errors ->
          Repo.rollback({:incomplete_quiz, errors})
      end
    end)
  end

  def quiz_completeness_errors(%Quiz{questions: questions}) when is_list(questions) do
    case questions do
      [] ->
        ["Add at least one question before publishing."]

      questions ->
        questions
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {question, index} ->
          question_completeness_errors(question, index)
        end)
    end
  end

  ## Submissions

  @doc """
  Scores and records a learner's quiz attempt.

  Scoring is always against the quiz's *currently published* questions,
  re-fetched here rather than trusted from the caller — a stale or tampered
  `answers` map can only reference real, published question/option ids that
  are iterated from the trusted set; anything else is silently not counted
  (never raises, never inflates a score). Multiple attempts are allowed: a
  learner who fails can retake the quiz, and `passed_quiz?/2` considers any
  passing attempt, not only the most recent one.

  Returns `{:error, :quiz_not_ready}` if the quiz has no published questions
  yet, rather than dividing by zero or silently failing everyone.
  """
  def submit_quiz(%User{} = user, %Quiz{} = quiz, answers) when is_map(answers) do
    case list_published_questions(quiz) do
      [] ->
        {:error, :quiz_not_ready}

      questions ->
        normalized = stringify_answers(answers)
        correct_count = Enum.count(questions, &answer_correct?(&1, normalized))
        score_percent = round(correct_count / length(questions) * 100)
        passed = score_percent >= quiz.passing_score_percent

        %QuizSubmission{}
        |> QuizSubmission.changeset(%{
          quiz_id: quiz.id,
          user_id: user.id,
          answers: normalized,
          score_percent: score_percent,
          passed: passed,
          submitted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()
    end
  end

  def list_submissions_for_user(%User{id: user_id}, %Quiz{id: quiz_id}) do
    QuizSubmission
    |> where([s], s.user_id == ^user_id and s.quiz_id == ^quiz_id)
    |> order_by([s], desc: s.submitted_at, desc: s.id)
    |> Repo.all()
  end

  @doc """
  Whether a learner has ever passed this quiz, in any attempt.
  """
  def passed_quiz?(%User{id: user_id}, %Quiz{id: quiz_id}) do
    QuizSubmission
    |> where([s], s.user_id == ^user_id and s.quiz_id == ^quiz_id and s.passed == true)
    |> Repo.exists?()
  end

  ## PDF-driven question generation

  @doc """
  Records a new PDF-to-quiz generation request as `:pending` and returns it.
  The caller (an admin LiveView) is expected to enqueue
  `Wasomi.Assessments.Workers.GenerateQuizFromPDFWorker` right after this
  succeeds.
  """
  def create_generation(%Quiz{} = quiz, %User{} = user, source_filename) do
    %QuizGeneration{}
    |> QuizGeneration.changeset(%{
      quiz_id: quiz.id,
      requested_by_id: user.id,
      source_filename: source_filename,
      status: :pending
    })
    |> Repo.insert()
  end

  def get_generation!(id), do: Repo.get!(QuizGeneration, id)

  def list_generations_for_quiz(%Quiz{id: quiz_id}) do
    QuizGeneration
    |> where([g], g.quiz_id == ^quiz_id)
    |> order_by([g], desc: g.inserted_at, desc: g.id)
    |> Repo.all()
  end

  @doc """
  Subscribes the caller to generation status updates for this quiz, so an
  open admin LiveView can react without polling.
  """
  def subscribe_to_generation(%Quiz{id: quiz_id}) do
    Phoenix.PubSub.subscribe(Wasomi.PubSub, generation_topic(quiz_id))
  end

  def mark_generation_processing(%QuizGeneration{} = generation) do
    {:ok, updated} = update_generation(generation, %{status: :processing})
    broadcast_generation(updated)
    updated
  end

  def mark_generation_failed(%QuizGeneration{} = generation, error_message) do
    {:ok, updated} =
      update_generation(generation, %{status: :failed, error_message: error_message})

    broadcast_generation(updated)
    updated
  end

  @doc """
  Deletes every still-`:draft` question created by this specific generation
  batch, leaving already-published questions and drafts from any other
  generation (or added manually) untouched.
  """
  def discard_generation_drafts(%QuizGeneration{id: generation_id}) do
    Question
    |> where([q], q.quiz_generation_id == ^generation_id and q.status == :draft)
    |> Repo.delete_all()
  end

  @doc """
  Deletes every still-`:draft` question on this quiz, regardless of which
  generation batch (if any) created them.
  """
  def discard_all_drafts(%Quiz{id: quiz_id}) do
    Question
    |> where([q], q.quiz_id == ^quiz_id and q.status == :draft)
    |> Repo.delete_all()
  end

  @doc """
  Publishes every still-`:draft` question on this quiz in one statement, for
  an admin who has reviewed the whole batch and wants to publish it in one
  action rather than clicking Publish on each question individually.
  """
  def publish_all_drafts(%Quiz{id: quiz_id}) do
    Question
    |> where([q], q.quiz_id == ^quiz_id and q.status == :draft)
    |> Repo.update_all(set: [status: :published])
  end

  @doc """
  Inserts one `:draft` question (with options) per generated item, appended
  after the quiz's existing questions, then marks the generation `:ready`.

  A single malformed generated question (e.g. the model somehow produced
  zero correct options despite the JSON-schema constraint) is skipped rather
  than failing the whole batch — the admin already has to review every
  drafted question before publishing it, so losing one bad item is a much
  better outcome than discarding an otherwise-good batch and forcing a full
  retry. Only when *none* of the generated items could be inserted does this
  return an error (letting Oban retry the whole generation).
  """
  def create_draft_questions_and_mark_ready(%QuizGeneration{} = generation, drafts)
      when is_list(drafts) do
    quiz = get_quiz!(generation.quiz_id)
    starting_position = next_question_position(quiz)

    {created, _next_position} =
      Enum.reduce(drafts, {[], starting_position}, fn draft, {acc, position} ->
        case create_question(quiz, question_attrs(draft, position, generation.id)) do
          {:ok, question} -> {[question | acc], position + 1}
          {:error, _changeset} -> {acc, position}
        end
      end)

    created = Enum.reverse(created)

    if created == [] do
      {:error, :no_valid_questions_generated}
    else
      {:ok, updated} =
        update_generation(generation, %{
          status: :ready,
          questions_generated_count: length(created)
        })

      broadcast_generation(updated)
      {:ok, length(created)}
    end
  end

  defp next_question_position(%Quiz{id: quiz_id}) do
    Question
    |> where([q], q.quiz_id == ^quiz_id)
    |> select([q], max(q.position))
    |> Repo.one()
    |> case do
      nil -> 1
      max -> max + 1
    end
  end

  defp question_attrs(%{prompt: prompt, options: options}, position, generation_id) do
    %{
      prompt: prompt,
      status: :draft,
      position: position,
      quiz_generation_id: generation_id,
      question_options:
        options
        |> Enum.with_index(1)
        |> Enum.map(fn {option, idx} ->
          %{label: option.label, correct: option.correct, position: idx}
        end)
    }
  end

  defp update_generation(%QuizGeneration{} = generation, attrs) do
    generation
    |> QuizGeneration.changeset(attrs)
    |> Repo.update()
  end

  defp broadcast_generation(%QuizGeneration{} = generation) do
    Phoenix.PubSub.broadcast(
      Wasomi.PubSub,
      generation_topic(generation.quiz_id),
      {:quiz_generation_updated, generation}
    )
  end

  defp generation_topic(quiz_id), do: "quiz_generation:quiz:#{quiz_id}"

  defp stringify_answers(answers) do
    Map.new(answers, fn {question_id, option_id} ->
      {to_string(question_id), to_string(option_id)}
    end)
  end

  defp answer_correct?(%Question{id: id, question_options: options}, answers) do
    case Map.get(answers, to_string(id)) do
      nil -> false
      selected -> Enum.any?(options, &(to_string(&1.id) == selected and &1.correct))
    end
  end

  defp question_completeness_errors(question, index) do
    options = question.question_options
    prefix = "Question #{index}"

    []
    |> maybe_add_error(blank?(question.prompt), "#{prefix} needs question text.")
    |> maybe_add_error(length(options) < 2, "#{prefix} needs at least two options.")
    |> maybe_add_error(
      Enum.any?(options, &blank?(&1.label)),
      "#{prefix} has an option without text."
    )
    |> maybe_add_error(
      !Enum.any?(options, & &1.correct),
      "#{prefix} needs a correct answer."
    )
  end

  defp maybe_add_error(errors, true, error), do: errors ++ [error]
  defp maybe_add_error(errors, false, _error), do: errors

  defp blank?(value), do: !is_binary(value) or String.trim(value) == ""

  defp normalize_ids(ids) do
    ids
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, parsed} ->
      case Integer.parse(to_string(id)) do
        {id, ""} when id > 0 -> {:cont, {:ok, [id | parsed]}}
        _invalid -> {:halt, {:error, :invalid_order}}
      end
    end)
    |> case do
      {:ok, parsed} ->
        parsed = Enum.reverse(parsed)
        if Enum.uniq(parsed) == parsed, do: {:ok, parsed}, else: {:error, :invalid_order}

      error ->
        error
    end
  end

  defp persist_question_order(questions, question_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    offset = length(questions) * 2 + 1

    Enum.each(questions, fn question ->
      Question
      |> where([item], item.id == ^question.id)
      |> Repo.update_all(set: [position: offset + question.position, updated_at: now])
    end)

    question_ids
    |> Enum.with_index(1)
    |> Enum.each(fn {id, position} ->
      Question
      |> where([item], item.id == ^id)
      |> Repo.update_all(set: [position: position, updated_at: now])
    end)

    :reordered
  end
end
