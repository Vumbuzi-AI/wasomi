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

  alias Wasomi.Assessments.{
    LectureQuiz,
    LectureQuizGeneration,
    LectureQuizQuestion,
    LectureQuizSubmission,
    Question,
    Quiz,
    QuizGeneration,
    QuizSubmission
  }

  alias Wasomi.Assessments.Workers.GenerateLectureQuizWorker
  alias Wasomi.Catalog.CourseModule
  alias Wasomi.Catalog.Lecture
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
  Counts lecture-quiz questions (any status) for every lecture in a course,
  keyed by `lecture_id`. Lectures with no lecture quiz, or no questions
  generated yet, are simply absent from the result — callers should use
  `Map.has_key?/2` to ask "has this lecture's quiz actually been generated,"
  not `Map.get/3` with a `0` default.
  """
  def count_lecture_quiz_questions_by_lecture(course_id) do
    LectureQuizQuestion
    |> join(:inner, [q], quiz in LectureQuiz, on: quiz.id == q.lecture_quiz_id)
    |> join(:inner, [q, quiz], lecture in Lecture, on: lecture.id == quiz.lecture_id)
    |> join(:inner, [q, _quiz, lecture], module in CourseModule,
      on: module.id == lecture.module_id
    )
    |> where([_q, _quiz, _lecture, module], module.course_id == ^course_id)
    |> group_by([_q, _quiz, lecture, _module], lecture.id)
    |> select([q, _quiz, lecture, _module], {lecture.id, count(q.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Lists the prompt text of every `:published` lecture-quiz question across
  every lecture in a module, so module-quiz generation can seed its prompt
  with what's already been asked at the lecture level instead of
  re-deriving (and duplicating) the same coverage.
  """
  def list_lecture_quiz_question_prompts_for_module(module_id) do
    LectureQuizQuestion
    |> join(:inner, [q], quiz in LectureQuiz, on: quiz.id == q.lecture_quiz_id)
    |> join(:inner, [q, quiz], lecture in Lecture, on: lecture.id == quiz.lecture_id)
    |> where([q, _quiz, lecture], lecture.module_id == ^module_id and q.status == :published)
    |> select([q], q.prompt)
    |> Repo.all()
  end

  @doc """
  Checks if every lecture in a module has a lecture quiz.
  """
  def module_ready_for_quiz_generation?(%Wasomi.Catalog.CourseModule{} = module) do
    lectures = Wasomi.Catalog.list_lectures_for_module(module.id)
    lectures != [] and Enum.all?(lectures, fn l -> get_lecture_quiz(l.id) != nil end)
  end

  def module_ready_for_quiz_generation?(module_id)
      when is_integer(module_id) or is_binary(module_id) do
    lectures = Wasomi.Catalog.list_lectures_for_module(module_id)
    lectures != [] and Enum.all?(lectures, fn l -> get_lecture_quiz(l.id) != nil end)
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
  Each enrolled user's latest attempt per module quiz in a course, keyed by
  `user_id`, as a list of `%{quiz_title:, score_percent:, passed:}` maps —
  only for quizzes the user has actually attempted at least once (a user
  absent from the result, or missing a particular quiz from their list,
  simply hasn't attempted it yet).

  For the admin course view's enrolled-students table: two queries total
  regardless of student count, so computing this per row doesn't become an
  N+1 the way calling `list_submissions_for_user/2` per (student, quiz) pair
  would.
  """
  def latest_quiz_scores_by_user(course_id) do
    quiz_titles =
      Quiz
      |> join(:inner, [q], module in CourseModule, on: module.id == q.module_id)
      |> where([_q, module], module.course_id == ^course_id)
      |> select([q], {q.id, q.title})
      |> Repo.all()
      |> Map.new()

    quiz_ids = Map.keys(quiz_titles)

    QuizSubmission
    |> where([s], s.quiz_id in ^quiz_ids)
    |> order_by([s], asc: s.user_id, asc: s.quiz_id, desc: s.submitted_at, desc: s.id)
    |> Repo.all()
    |> Enum.uniq_by(&{&1.user_id, &1.quiz_id})
    |> Enum.group_by(& &1.user_id, fn submission ->
      %{
        quiz_title: Map.fetch!(quiz_titles, submission.quiz_id),
        score_percent: submission.score_percent,
        passed: submission.passed
      }
    end)
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
    Repo.transaction(fn ->
      case question
           |> Ecto.Changeset.change(status: :published)
           |> Repo.update() do
        {:ok, updated_question} ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          Quiz
          |> where([q], q.id == ^question.quiz_id)
          |> Repo.update_all(set: [active: true, published_at: now])

          updated_question

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
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
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      Question
      |> where([q], q.quiz_id == ^quiz_id and q.status == :draft)
      |> Repo.update_all(set: [status: :published, updated_at: now])

    Quiz
    |> where([q], q.id == ^quiz_id)
    |> Repo.update_all(set: [active: true, published_at: now])

    {count, nil}
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

  ## Lecture quizzes

  @doc """
  Gets the quiz for a lecture, if one exists. A lecture has at most one quiz.
  """
  def get_lecture_quiz(%Lecture{id: lecture_id}), do: get_lecture_quiz(lecture_id)
  def get_lecture_quiz(lecture_id), do: Repo.get_by(LectureQuiz, lecture_id: lecture_id)

  def get_lecture_quiz_with_questions!(id) do
    questions_query = from(question in LectureQuizQuestion, order_by: [asc: question.position])

    options_query =
      from(option in Wasomi.Assessments.LectureQuizQuestionOption,
        order_by: [asc: option.position]
      )

    LectureQuiz
    |> Repo.get!(id)
    |> Repo.preload([:lecture, questions: {questions_query, question_options: options_query}])
  end

  @doc """
  Lists a lecture quiz's `:published` questions with their options, ordered
  — the only question set a learner should ever be scored against. Mirrors
  `list_published_questions/1`, minus the extra `quiz.active` check that
  function has — see the `LectureQuiz` moduledoc for why.
  """
  def list_published_lecture_quiz_questions(%LectureQuiz{id: lecture_quiz_id}) do
    options_query =
      from(option in Wasomi.Assessments.LectureQuizQuestionOption,
        order_by: [asc: option.position]
      )

    LectureQuizQuestion
    |> where([q], q.lecture_quiz_id == ^lecture_quiz_id and q.status == :published)
    |> order_by([q], asc: q.position)
    |> preload(question_options: ^options_query)
    |> Repo.all()
  end

  @doc """
  Whether a lecture quiz has enough reviewed content for a learner to take
  it — used by `Wasomi.Learning.lecture_unlocked?/3` to decide whether a
  lecture's quiz should gate the next lecture at all. A quiz with zero
  published questions (still mid-generation, or awaiting review) never
  blocks anyone, same as a lecture with no quiz at all.
  """
  def lecture_quiz_ready_for_learners?(%LectureQuiz{id: lecture_quiz_id}) do
    LectureQuizQuestion
    |> where([q], q.lecture_quiz_id == ^lecture_quiz_id and q.status == :published)
    |> Repo.exists?()
  end

  @doc """
  Scores and records a learner's lecture-quiz attempt. Mirrors `submit_quiz/3`.
  """
  def submit_lecture_quiz(%User{} = user, %LectureQuiz{} = quiz, answers) when is_map(answers) do
    case list_published_lecture_quiz_questions(quiz) do
      [] ->
        {:error, :quiz_not_ready}

      questions ->
        normalized = stringify_answers(answers)
        correct_count = Enum.count(questions, &lecture_quiz_answer_correct?(&1, normalized))
        score_percent = round(correct_count / length(questions) * 100)
        passed = score_percent >= quiz.passing_score_percent

        %LectureQuizSubmission{}
        |> LectureQuizSubmission.changeset(%{
          lecture_quiz_id: quiz.id,
          user_id: user.id,
          answers: normalized,
          score_percent: score_percent,
          passed: passed,
          submitted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()
    end
  end

  def list_lecture_quiz_submissions_for_user(%User{id: user_id}, %LectureQuiz{id: lecture_quiz_id}) do
    LectureQuizSubmission
    |> where([s], s.user_id == ^user_id and s.lecture_quiz_id == ^lecture_quiz_id)
    |> order_by([s], desc: s.submitted_at, desc: s.id)
    |> Repo.all()
  end

  @doc """
  Whether a learner has ever passed this lecture quiz, in any attempt.
  """
  def passed_lecture_quiz?(%User{id: user_id}, %LectureQuiz{id: lecture_quiz_id}) do
    LectureQuizSubmission
    |> where(
      [s],
      s.user_id == ^user_id and s.lecture_quiz_id == ^lecture_quiz_id and s.passed == true
    )
    |> Repo.exists?()
  end

  defp lecture_quiz_answer_correct?(
         %LectureQuizQuestion{id: id, question_options: options},
         answers
       ) do
    case Map.get(answers, to_string(id)) do
      nil -> false
      selected -> Enum.any?(options, &(to_string(&1.id) == selected and &1.correct))
    end
  end

  @doc """
  Gets or creates the quiz for a lecture, so the admin resource-picker
  doesn't need a separate "create the quiz" step before it can start a
  generation.
  """
  def ensure_lecture_quiz(%Lecture{} = lecture) do
    case get_lecture_quiz(lecture.id) do
      nil -> create_lecture_quiz(lecture, %{title: "#{lecture.title} quiz"})
      quiz -> {:ok, quiz}
    end
  end

  def create_lecture_quiz(%Lecture{} = lecture, attrs) do
    %LectureQuiz{}
    |> LectureQuiz.changeset(Map.put(attrs, :lecture_id, lecture.id))
    |> Repo.insert()
  end

  def create_lecture_quiz_question(%LectureQuiz{} = quiz, attrs) do
    %LectureQuizQuestion{lecture_quiz_id: quiz.id}
    |> LectureQuizQuestion.changeset(attrs)
    |> Repo.insert()
  end

  def change_lecture_quiz_question(%LectureQuizQuestion{} = question, attrs \\ %{}) do
    LectureQuizQuestion.changeset(question, attrs)
  end

  def update_lecture_quiz_question(%LectureQuizQuestion{} = question, attrs) do
    question
    |> LectureQuizQuestion.changeset(attrs)
    |> Repo.update()
  end

  def reorder_lecture_quiz_questions(%LectureQuiz{id: lecture_quiz_id}, question_ids)
      when is_list(question_ids) do
    with {:ok, question_ids} <- normalize_ids(question_ids) do
      Repo.transaction(fn ->
        questions =
          LectureQuizQuestion
          |> where([question], question.lecture_quiz_id == ^lecture_quiz_id)
          |> order_by([question], asc: question.position)
          |> lock("FOR UPDATE")
          |> Repo.all()

        if Enum.sort(Enum.map(questions, & &1.id)) == Enum.sort(question_ids) do
          persist_lecture_quiz_question_order(questions, question_ids)
        else
          Repo.rollback(:invalid_order)
        end
      end)
    end
  end

  defp persist_lecture_quiz_question_order(questions, target_ids) do
    questions
    |> Enum.with_index(1)
    |> Enum.each(fn {question, idx} ->
      question
      |> Ecto.Changeset.change(position: -idx)
      |> Repo.update!()
    end)

    target_ids
    |> Enum.with_index(1)
    |> Enum.each(fn {id, new_pos} ->
      LectureQuizQuestion
      |> where([q], q.id == ^id)
      |> Repo.update_all(set: [position: new_pos])
    end)

    :ok
  end

  def get_lecture_quiz_question!(id), do: Repo.get!(LectureQuizQuestion, id)

  def delete_lecture_quiz_question(%LectureQuizQuestion{} = question), do: Repo.delete(question)

  @doc """
  Marks a draft lecture-quiz question as reviewed and visible to learners.
  """
  def publish_lecture_quiz_question(%LectureQuizQuestion{} = question) do
    question
    |> Ecto.Changeset.change(status: :published)
    |> Repo.update()
  end

  @doc """
  Publishes every still-`:draft` question on this lecture quiz in one
  statement, same "review the whole batch at once" convenience as
  `publish_all_drafts/1`.
  """
  def publish_all_lecture_quiz_drafts(%LectureQuiz{id: lecture_quiz_id}) do
    LectureQuizQuestion
    |> where([q], q.lecture_quiz_id == ^lecture_quiz_id and q.status == :draft)
    |> Repo.update_all(set: [status: :published])
  end

  @doc """
  Deletes every still-`:draft` question on this lecture quiz, regardless of
  which generation batch (if any) created them.
  """
  def discard_all_lecture_quiz_drafts(%LectureQuiz{id: lecture_quiz_id}) do
    LectureQuizQuestion
    |> where([q], q.lecture_quiz_id == ^lecture_quiz_id and q.status == :draft)
    |> Repo.delete_all()
  end

  @doc """
  Starts a lecture-quiz generation: ensures the lecture has a quiz row,
  records the admin's resource/difficulty/count choices, and enqueues
  `Wasomi.Assessments.Workers.GenerateLectureQuizWorker` to do the actual
  drafting in the background.
  """
  def start_lecture_quiz_generation(%Lecture{} = lecture, %User{} = user, attrs) do
    with {:ok, quiz} <- ensure_lecture_quiz(lecture),
         {:ok, generation} <- create_lecture_quiz_generation(quiz, user, attrs) do
      GenerateLectureQuizWorker.enqueue(generation.id)
      {:ok, generation}
    end
  end

  def create_lecture_quiz_generation(%LectureQuiz{} = quiz, %User{} = user, attrs) do
    %LectureQuizGeneration{}
    |> LectureQuizGeneration.changeset(
      Map.merge(attrs, %{lecture_quiz_id: quiz.id, requested_by_id: user.id, status: :pending})
    )
    |> Repo.insert()
  end

  def get_lecture_quiz_generation!(id), do: Repo.get!(LectureQuizGeneration, id)

  @doc """
  Loads the lecture a generation's source text should be read from, without
  the caller needing to know it's reached through `lecture_quiz`.
  """
  def get_lecture_for_generation!(%LectureQuizGeneration{} = generation) do
    generation
    |> Repo.preload(lecture_quiz: :lecture)
    |> Map.fetch!(:lecture_quiz)
    |> Map.fetch!(:lecture)
  end

  def list_lecture_quiz_generations(%LectureQuiz{id: lecture_quiz_id}) do
    LectureQuizGeneration
    |> where([g], g.lecture_quiz_id == ^lecture_quiz_id)
    |> order_by([g], desc: g.inserted_at, desc: g.id)
    |> Repo.all()
  end

  @doc """
  Subscribes the caller to generation status updates for this lecture quiz,
  so an open admin LiveView can react without polling.
  """
  def subscribe_to_lecture_quiz_generation(%LectureQuiz{id: lecture_quiz_id}) do
    Phoenix.PubSub.subscribe(Wasomi.PubSub, lecture_quiz_generation_topic(lecture_quiz_id))
  end

  def mark_lecture_quiz_generation_processing(%LectureQuizGeneration{} = generation) do
    {:ok, updated} = update_lecture_quiz_generation(generation, %{status: :processing})
    broadcast_lecture_quiz_generation(updated)
    updated
  end

  def mark_lecture_quiz_generation_failed(%LectureQuizGeneration{} = generation, error_message) do
    {:ok, updated} =
      update_lecture_quiz_generation(generation, %{status: :failed, error_message: error_message})

    broadcast_lecture_quiz_generation(updated)
    updated
  end

  @doc """
  Inserts one `:draft` question (with options) per generated item, appended
  after the lecture quiz's existing questions, then marks the generation
  `:ready` — same "skip malformed items, only fail the batch if none landed"
  behavior as `create_draft_questions_and_mark_ready/2`.
  """
  def create_lecture_quiz_draft_questions_and_mark_ready(
        %LectureQuizGeneration{} = generation,
        drafts
      )
      when is_list(drafts) do
    quiz = Repo.get!(LectureQuiz, generation.lecture_quiz_id)
    starting_position = next_lecture_quiz_question_position(quiz)

    {created, _next_position} =
      Enum.reduce(drafts, {[], starting_position}, fn draft, {acc, position} ->
        case create_lecture_quiz_question(
               quiz,
               lecture_quiz_question_attrs(draft, position, generation.id)
             ) do
          {:ok, question} -> {[question | acc], position + 1}
          {:error, _changeset} -> {acc, position}
        end
      end)

    created = Enum.reverse(created)

    if created == [] do
      {:error, :no_valid_questions_generated}
    else
      {:ok, updated} =
        update_lecture_quiz_generation(generation, %{
          status: :ready,
          questions_generated_count: length(created)
        })

      broadcast_lecture_quiz_generation(updated)
      {:ok, length(created)}
    end
  end

  defp next_lecture_quiz_question_position(%LectureQuiz{id: lecture_quiz_id}) do
    LectureQuizQuestion
    |> where([q], q.lecture_quiz_id == ^lecture_quiz_id)
    |> select([q], max(q.position))
    |> Repo.one()
    |> case do
      nil -> 1
      max -> max + 1
    end
  end

  defp lecture_quiz_question_attrs(%{prompt: prompt, options: options}, position, generation_id) do
    %{
      prompt: prompt,
      status: :draft,
      position: position,
      lecture_quiz_generation_id: generation_id,
      question_options:
        options
        |> Enum.with_index(1)
        |> Enum.map(fn {option, idx} ->
          %{label: option.label, correct: option.correct, position: idx}
        end)
    }
  end

  defp update_lecture_quiz_generation(%LectureQuizGeneration{} = generation, attrs) do
    generation
    |> LectureQuizGeneration.changeset(attrs)
    |> Repo.update()
  end

  defp broadcast_lecture_quiz_generation(%LectureQuizGeneration{} = generation) do
    Phoenix.PubSub.broadcast(
      Wasomi.PubSub,
      lecture_quiz_generation_topic(generation.lecture_quiz_id),
      {:lecture_quiz_generation_updated, generation}
    )
  end

  defp lecture_quiz_generation_topic(lecture_quiz_id),
    do: "lecture_quiz_generation:lecture_quiz:#{lecture_quiz_id}"
end
