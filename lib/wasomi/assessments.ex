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
    Flashcard,
    FlashcardProgress,
    FlashcardSet,
    LectureQuiz,
    LectureQuizGeneration,
    LectureQuizQuestion,
    LectureQuizSubmission,
    PracticeQuestion,
    PracticeQuestionOption,
    PracticeSet,
    PracticeSetQuestion,
    PracticeSetQuestionOption,
    PracticeSetQuestionProgress,
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

    if quiz_ids == [],
      do: %{},
      else:
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
  Returns a `MapSet` of `quiz_id`s for which the specified user has submitted at least one attempt in a course.
  """
  def completed_quiz_ids_for_user(user_id, course_id) do
    QuizSubmission
    |> join(:inner, [s], q in Quiz, on: q.id == s.quiz_id)
    |> join(:inner, [s, q], m in CourseModule, on: m.id == q.module_id)
    |> where([s, _q, m], s.user_id == ^user_id and m.course_id == ^course_id)
    |> select([s], s.quiz_id)
    |> Repo.all()
    |> MapSet.new()
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

  ## Practice questions

  @doc """
  Lists all practice questions for a module (any status), ordered by position.
  Used by the admin authoring view.
  """
  def list_all_practice_questions(%CourseModule{id: module_id}) do
    options_query =
      from(o in PracticeQuestionOption, order_by: [asc: o.position])

    PracticeQuestion
    |> where([q], q.module_id == ^module_id)
    |> order_by([q], asc: q.position)
    |> preload([q], practice_question_options: ^options_query)
    |> Repo.all()
  end

  @doc """
  Lists only `:published` practice questions for a module with options preloaded.
  Used by the learner course player.
  """
  def list_published_practice_questions(%CourseModule{id: module_id}) do
    options_query =
      from(o in PracticeQuestionOption, order_by: [asc: o.position])

    PracticeQuestion
    |> where([q], q.module_id == ^module_id and q.status == :published)
    |> order_by([q], asc: q.position)
    |> preload([q], practice_question_options: ^options_query)
    |> Repo.all()
  end

  @doc """
  Returns a map of `module_id => [published PracticeQuestion]` for every
  module in a course that has at least one published practice question.
  Used by the course player to build the sidenav and avoid N+1 queries.
  """
  def published_practice_questions_by_module(course_id) do
    options_query =
      from(o in PracticeQuestionOption, order_by: [asc: o.position])

    PracticeQuestion
    |> join(:inner, [q], m in CourseModule, on: m.id == q.module_id)
    |> where([q, m], m.course_id == ^course_id and q.status == :published)
    |> order_by([q, _m], asc: q.position)
    |> preload([q, _m], practice_question_options: ^options_query)
    |> Repo.all()
    |> Enum.group_by(& &1.module_id)
  end

  def get_practice_question!(id) do
    options_query = from(o in PracticeQuestionOption, order_by: [asc: o.position])
    Repo.get!(PracticeQuestion, id) |> Repo.preload(practice_question_options: options_query)
  end

  def create_practice_question(%CourseModule{} = module, attrs) do
    position = next_practice_question_position(module.id)

    %PracticeQuestion{module_id: module.id, position: position}
    |> PracticeQuestion.changeset(attrs)
    |> Repo.insert()
  end

  def update_practice_question(%PracticeQuestion{} = question, attrs) do
    question
    |> PracticeQuestion.changeset(attrs)
    |> Repo.update()
  end

  def delete_practice_question(%PracticeQuestion{} = question), do: Repo.delete(question)

  def change_practice_question(%PracticeQuestion{} = question, attrs \\ %{}),
    do: PracticeQuestion.changeset(question, attrs)

  @doc """
  Marks a practice question as `:published`, making it visible to learners.
  """
  def publish_practice_question(%PracticeQuestion{} = question) do
    question
    |> Ecto.Changeset.change(status: :published)
    |> Repo.update()
  end

  defp next_practice_question_position(module_id) do
    max_pos =
      PracticeQuestion
      |> where([q], q.module_id == ^module_id)
      |> select([q], max(q.position))
      |> Repo.one()

    (max_pos || 0) + 1
  end

  @doc """
  Generates AI practice questions on-demand for a module using its lecture content, resources, and transcripts.
  Deduplicates generated questions against any existing module quiz questions, lecture quiz questions, or prior practice questions.
  All generated questions are inserted as `:published` practice questions.
  """
  def generate_practice_questions_for_module(%CourseModule{} = module, opts \\ []) do
    text = gather_module_text(module)
    count = Keyword.get(opts, :count, 5)
    existing_prompts = list_existing_question_prompts_for_module(module.id)

    generator =
      Application.get_env(
        :wasomi,
        :question_generator,
        Wasomi.Assessments.QuestionGenerator.OpenAI
      )

    generator_opts = [
      min_count: count,
      max_count: count,
      avoid_duplicating: existing_prompts
    ]

    case generator.generate_questions(text, generator_opts) do
      {:ok, draft_questions} ->
        questions =
          Enum.map(draft_questions, fn draft ->
            options_attrs =
              draft.options
              |> Enum.with_index(1)
              |> Map.new(fn {opt, idx} ->
                {to_string(idx),
                 %{
                   "label" => opt.label,
                   "correct" => opt.correct,
                   "position" => idx
                 }}
              end)

            attrs = %{
              "prompt" => draft.prompt,
              "explanation" =>
                Map.get(draft, :explanation, "Generated from module study material."),
              "status" => "published",
              "practice_question_options" => options_attrs
            }

            {:ok, question} = create_practice_question(module, attrs)
            get_practice_question!(question.id)
          end)

        {:ok, questions}

      error ->
        error
    end
  end

  @doc """
  Returns a list of all existing question prompts in the module (from the module quiz,
  all lecture quizzes, and existing practice questions) to prevent duplicate questions.
  """
  def list_existing_question_prompts_for_module(module_id) do
    module_quiz_prompts =
      from(q in Question,
        join: z in Quiz,
        on: z.id == q.quiz_id,
        where: z.module_id == ^module_id,
        select: q.prompt
      )
      |> Repo.all()

    lecture_quiz_prompts =
      from(lq in LectureQuizQuestion,
        join: lz in LectureQuiz,
        on: lz.id == lq.lecture_quiz_id,
        join: l in Lecture,
        on: l.id == lz.lecture_id,
        where: l.module_id == ^module_id,
        select: lq.prompt
      )
      |> Repo.all()

    practice_prompts =
      from(pq in PracticeQuestion,
        where: pq.module_id == ^module_id,
        select: pq.prompt
      )
      |> Repo.all()

    (module_quiz_prompts ++ lecture_quiz_prompts ++ practice_prompts)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp gather_module_text(%CourseModule{id: module_id} = module) do
    lectures =
      Lecture
      |> where([l], l.module_id == ^module_id)
      |> order_by([l], asc: l.position)
      |> Repo.all()

    resource_reader =
      Application.get_env(
        :wasomi,
        :lecture_resource_reader,
        Wasomi.Assessments.LectureResourceReader.Storage
      )

    lecture_texts =
      Enum.map(lectures, fn lecture ->
        transcript_text =
          case Wasomi.Catalog.get_lecture_transcript(lecture.id) do
            %{status: :ready, text: t} when is_binary(t) -> t
            _ -> ""
          end

        resources =
          from(r in Wasomi.Catalog.LectureResource,
            where: r.lecture_id == ^lecture.id,
            order_by: [asc: r.position]
          )
          |> Repo.all()

        resource_texts =
          Enum.map(resources, fn res ->
            case resource_reader.extract_text(res) do
              {:ok, text} when is_binary(text) -> text
              _ -> ""
            end
          end)
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n\n")

        parts = [
          lecture.description,
          transcript_text,
          resource_texts
        ]

        parts
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join("\n\n")
      end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n---\n\n")

    module_title = module.title || "Module"
    module_desc = Map.get(module, :description) || ""

    if String.trim(lecture_texts) == "" do
      "Subject Matter Domain: #{module_title}\n\nOverview:\n#{module_desc}"
    else
      "Subject Matter Domain: #{module_title}\n\nOverview:\n#{module_desc}\n\nStudy Material:\n#{lecture_texts}"
    end
  end

  ## Flashcards
  #
  # Self-study content: there's no admin authoring step, so (unlike
  # `Quiz`/`QuizGeneration`) generation status lives directly on the set
  # itself rather than a separate generation record, and a set is visible
  # to learners the moment it's `:ready` — every card in it is already
  # "published" by definition.

  @doc """
  Gets or creates the flashcard set for a module or a single lecture.
  Learner-triggered generation always needs a row to flip to `:processing`,
  and — unlike the admin-driven quiz flow — multiple learners can open the
  same scope's Flashcards section at once, so a losing concurrent insert
  falls back to re-fetching the winner's row instead of erroring.
  """
  def get_or_create_flashcard_set(%CourseModule{id: module_id}),
    do: do_get_or_create_flashcard_set(module_id: module_id)

  def get_or_create_flashcard_set(%Lecture{id: lecture_id}),
    do: do_get_or_create_flashcard_set(lecture_id: lecture_id)

  defp do_get_or_create_flashcard_set(scope) do
    case Repo.get_by(FlashcardSet, scope) do
      nil ->
        %FlashcardSet{}
        |> FlashcardSet.changeset(Enum.into(scope, %{status: :pending}))
        |> Repo.insert()
        |> case do
          {:ok, set} -> {:ok, set}
          {:error, _changeset} -> {:ok, Repo.get_by!(FlashcardSet, scope)}
        end

      set ->
        {:ok, set}
    end
  end

  def get_flashcard_set!(id), do: Repo.get!(FlashcardSet, id)

  @doc """
  Subscribes the caller to status updates for this module's or lecture's
  flashcard set, so an open LiveView can react to generation finishing
  without polling.
  """
  def subscribe_to_flashcard_set(%CourseModule{} = module),
    do: Phoenix.PubSub.subscribe(Wasomi.PubSub, flashcard_set_topic(module))

  def subscribe_to_flashcard_set(%Lecture{} = lecture),
    do: Phoenix.PubSub.subscribe(Wasomi.PubSub, flashcard_set_topic(lecture))

  def mark_flashcard_set_processing(%FlashcardSet{} = set) do
    {:ok, updated} = update_flashcard_set(set, %{status: :processing})
    broadcast_flashcard_set(updated)
    updated
  end

  def mark_flashcard_set_failed(%FlashcardSet{} = set, error_message) do
    {:ok, updated} =
      update_flashcard_set(set, %{status: :failed, error_message: error_message})

    broadcast_flashcard_set(updated)
    updated
  end

  @doc """
  Inserts one flashcard per generated item and marks the set `:ready` —
  same "skip malformed items, only fail the batch if none landed" behavior
  as `create_draft_questions_and_mark_ready/2`.
  """
  def mark_flashcard_set_ready(%FlashcardSet{} = set, cards) when is_list(cards) do
    {created, _next_position} =
      Enum.reduce(cards, {[], 1}, fn card, {acc, position} ->
        case create_flashcard(set, Map.put(card, :position, position)) do
          {:ok, flashcard} -> {[flashcard | acc], position + 1}
          {:error, _changeset} -> {acc, position}
        end
      end)

    created = Enum.reverse(created)

    if created == [] do
      {:error, :no_valid_flashcards_generated}
    else
      {:ok, updated} =
        update_flashcard_set(set, %{
          status: :ready,
          cards_generated_count: length(created),
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      broadcast_flashcard_set(updated)
      {:ok, length(created)}
    end
  end

  defp create_flashcard(%FlashcardSet{id: flashcard_set_id}, attrs) do
    %Flashcard{}
    |> Flashcard.changeset(Map.put(attrs, :flashcard_set_id, flashcard_set_id))
    |> Repo.insert()
  end

  def list_flashcards(%FlashcardSet{id: flashcard_set_id}) do
    Flashcard
    |> where([f], f.flashcard_set_id == ^flashcard_set_id)
    |> order_by([f], asc: f.position)
    |> Repo.all()
  end

  @doc """
  Every flashcard in a set with that user's own progress preloaded (`nil`
  for a card they haven't reviewed yet), so the review UI can render
  known/review-again state and a "N known of M" count without an N+1
  lookup per card.
  """
  def list_flashcards_with_progress(%FlashcardSet{id: flashcard_set_id}, %User{id: user_id}) do
    progress_by_flashcard_id =
      FlashcardProgress
      |> where([p], p.user_id == ^user_id)
      |> Repo.all()
      |> Map.new(&{&1.flashcard_id, &1})

    %FlashcardSet{id: flashcard_set_id}
    |> list_flashcards()
    |> Enum.map(fn flashcard -> {flashcard, Map.get(progress_by_flashcard_id, flashcard.id)} end)
  end

  @doc """
  Records (or updates) a learner's known/review-again call on a flashcard.
  """
  def record_flashcard_progress(%User{id: user_id}, %Flashcard{id: flashcard_id}, status)
      when status in [:known, :review_again] do
    %FlashcardProgress{}
    |> FlashcardProgress.changeset(%{
      flashcard_id: flashcard_id,
      user_id: user_id,
      status: status,
      reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert(
      on_conflict: {:replace, [:status, :reviewed_at, :updated_at]},
      conflict_target: [:flashcard_id, :user_id],
      returning: true
    )
  end

  defp update_flashcard_set(%FlashcardSet{} = set, attrs) do
    set
    |> FlashcardSet.changeset(attrs)
    |> Repo.update()
  end

  defp broadcast_flashcard_set(%FlashcardSet{} = set) do
    Phoenix.PubSub.broadcast(
      Wasomi.PubSub,
      flashcard_set_topic(set),
      {:flashcard_set_updated, set}
    )
  end

  defp flashcard_set_topic(%CourseModule{id: id}), do: "flashcard_set:module:#{id}"
  defp flashcard_set_topic(%Lecture{id: id}), do: "flashcard_set:lecture:#{id}"

  defp flashcard_set_topic(%FlashcardSet{module_id: id}) when not is_nil(id),
    do: "flashcard_set:module:#{id}"

  defp flashcard_set_topic(%FlashcardSet{lecture_id: id}) when not is_nil(id),
    do: "flashcard_set:lecture:#{id}"

  ## Practice questions
  #
  # "Extra practice" — self-study, per-module, same set-level-status/no-draft
  # shape as Flashcards above, but reuses the existing
  # `Wasomi.Assessments.QuestionGenerator` behaviour (same prompt/options
  # shape as quiz generation) rather than needing a generator of its own.

  @doc """
  Gets or creates the practice set for a module or a single lecture.
  Mirrors `get_or_create_flashcard_set/1`, including the same
  concurrent-learner fallback.
  """
  def get_or_create_practice_set(%CourseModule{id: module_id}),
    do: do_get_or_create_practice_set(module_id: module_id)

  def get_or_create_practice_set(%Lecture{id: lecture_id}),
    do: do_get_or_create_practice_set(lecture_id: lecture_id)

  defp do_get_or_create_practice_set(scope) do
    case Repo.get_by(PracticeSet, scope) do
      nil ->
        %PracticeSet{}
        |> PracticeSet.changeset(Enum.into(scope, %{status: :pending}))
        |> Repo.insert()
        |> case do
          {:ok, quiz} -> {:ok, quiz}
          {:error, _changeset} -> {:ok, Repo.get_by!(PracticeSet, scope)}
        end

      quiz ->
        {:ok, quiz}
    end
  end

  def get_practice_set!(id), do: Repo.get!(PracticeSet, id)

  @doc """
  Subscribes the caller to status updates for this module's or lecture's
  practice set, so an open LiveView can react to generation finishing
  without polling.
  """
  def subscribe_to_practice_set(%CourseModule{} = module),
    do: Phoenix.PubSub.subscribe(Wasomi.PubSub, practice_set_topic(module))

  def subscribe_to_practice_set(%Lecture{} = lecture),
    do: Phoenix.PubSub.subscribe(Wasomi.PubSub, practice_set_topic(lecture))

  def mark_practice_set_processing(%PracticeSet{} = quiz) do
    {:ok, updated} = update_practice_set(quiz, %{status: :processing})
    broadcast_practice_set(updated)
    updated
  end

  def mark_practice_set_failed(%PracticeSet{} = quiz, error_message) do
    {:ok, updated} =
      update_practice_set(quiz, %{status: :failed, error_message: error_message})

    broadcast_practice_set(updated)
    updated
  end

  @doc """
  Inserts one practice question (with options) per generated item and
  marks the quiz `:ready` — same "skip malformed items, only fail the
  batch if none landed" behavior as `create_draft_questions_and_mark_ready/2`.
  """
  def mark_practice_set_ready(%PracticeSet{} = quiz, drafts) when is_list(drafts) do
    {created, _next_position} =
      Enum.reduce(drafts, {[], 1}, fn draft, {acc, position} ->
        case create_practice_set_question(quiz, practice_set_question_attrs(draft, position)) do
          {:ok, question} -> {[question | acc], position + 1}
          {:error, _changeset} -> {acc, position}
        end
      end)

    created = Enum.reverse(created)

    if created == [] do
      {:error, :no_valid_questions_generated}
    else
      {:ok, updated} =
        update_practice_set(quiz, %{
          status: :ready,
          questions_generated_count: length(created),
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      broadcast_practice_set(updated)
      {:ok, length(created)}
    end
  end

  defp create_practice_set_question(%PracticeSet{id: practice_set_id}, attrs) do
    %PracticeSetQuestion{}
    |> PracticeSetQuestion.changeset(Map.put(attrs, :practice_set_id, practice_set_id))
    |> Repo.insert()
  end

  defp practice_set_question_attrs(%{prompt: prompt, options: options} = draft, position) do
    %{
      prompt: prompt,
      explanation: Map.get(draft, :explanation),
      position: position,
      practice_set_question_options:
        options
        |> Enum.with_index(1)
        |> Enum.map(fn {option, idx} ->
          %{label: option.label, correct: option.correct, position: idx}
        end)
    }
  end

  def list_practice_set_questions(%PracticeSet{id: practice_set_id}) do
    options_query =
      from(option in PracticeSetQuestionOption, order_by: [asc: option.position])

    PracticeSetQuestion
    |> where([q], q.practice_set_id == ^practice_set_id)
    |> order_by([q], asc: q.position)
    |> preload(practice_set_question_options: ^options_query)
    |> Repo.all()
  end

  @doc """
  Whether the given option id is the correct answer for a practice
  question, for the self-check UI's immediate right/wrong feedback.
  """
  def practice_answer_correct?(
        %PracticeSetQuestion{practice_set_question_options: options},
        option_id
      ) do
    Enum.any?(options, &(to_string(&1.id) == to_string(option_id) and &1.correct))
  end

  @doc """
  Records (or updates) a learner's most recent answer to a practice
  question. There's no scored submission here — just a running
  right/wrong log the "X of Y correct" counter reads from.
  """
  def record_practice_answer(
        %User{id: user_id},
        %PracticeSetQuestion{id: practice_set_question_id},
        last_correct
      )
      when is_boolean(last_correct) do
    %PracticeSetQuestionProgress{}
    |> PracticeSetQuestionProgress.changeset(%{
      practice_set_question_id: practice_set_question_id,
      user_id: user_id,
      last_correct: last_correct,
      answered_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert(
      on_conflict: {:replace, [:last_correct, :answered_at, :updated_at]},
      conflict_target: [:practice_set_question_id, :user_id],
      returning: true
    )
  end

  @doc """
  A user's practice-question progress for a quiz, keyed by `question_id`,
  so the self-check UI can restore "X of Y correct" and per-question
  right/wrong state on reload without an N+1 lookup per question.
  """
  def practice_progress_by_question(%PracticeSet{id: practice_set_id}, %User{id: user_id}) do
    PracticeSetQuestionProgress
    |> join(:inner, [p], q in PracticeSetQuestion, on: q.id == p.practice_set_question_id)
    |> where([p, q], q.practice_set_id == ^practice_set_id and p.user_id == ^user_id)
    |> select([p, q], {q.id, p})
    |> Repo.all()
    |> Map.new()
  end

  defp update_practice_set(%PracticeSet{} = quiz, attrs) do
    quiz
    |> PracticeSet.changeset(attrs)
    |> Repo.update()
  end

  defp broadcast_practice_set(%PracticeSet{} = quiz) do
    Phoenix.PubSub.broadcast(
      Wasomi.PubSub,
      practice_set_topic(quiz),
      {:practice_set_updated, quiz}
    )
  end

  defp practice_set_topic(%CourseModule{id: id}), do: "practice_set:module:#{id}"
  defp practice_set_topic(%Lecture{id: id}), do: "practice_set:lecture:#{id}"

  defp practice_set_topic(%PracticeSet{module_id: id}) when not is_nil(id),
    do: "practice_set:module:#{id}"

  defp practice_set_topic(%PracticeSet{lecture_id: id}) when not is_nil(id),
    do: "practice_set:lecture:#{id}"
end
