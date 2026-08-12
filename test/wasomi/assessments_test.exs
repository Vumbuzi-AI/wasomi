defmodule Wasomi.AssessmentsTest do
  use Wasomi.DataCase
  use Oban.Testing, repo: Wasomi.Repo

  alias Wasomi.Assessments
  alias Wasomi.Assessments.{Question, QuestionOption}
  alias Wasomi.Repo

  import Wasomi.AssessmentsFixtures
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures

  describe "quizzes" do
    test "create_quiz/2 with valid data creates a quiz scoped to a module" do
      module = course_module_fixture()

      assert {:ok, quiz} =
               Assessments.create_quiz(module, %{
                 title: "Module 1 Quiz",
                 passing_score_percent: 80
               })

      assert quiz.module_id == module.id
      assert quiz.passing_score_percent == 80
    end

    test "create_quiz/2 rejects an out-of-range passing score" do
      module = course_module_fixture()

      assert {:error, changeset} =
               Assessments.create_quiz(module, %{title: "Quiz", passing_score_percent: 150})

      assert "must be less than or equal to 100" in errors_on(changeset).passing_score_percent
    end

    test "create_quiz/2 rejects a second quiz for the same module" do
      module = course_module_fixture()
      quiz_fixture(%{module: module})

      assert {:error, changeset} = Assessments.create_quiz(module, %{title: "Second quiz"})
      assert "already has a quiz" in errors_on(changeset).module_id
    end

    test "delete_quiz/1 cascades to its questions and options" do
      quiz = quiz_fixture()
      question = question_fixture(%{quiz: quiz})
      option_ids = Enum.map(question.question_options, & &1.id)

      assert {:ok, _quiz} = Assessments.delete_quiz(quiz)

      assert Repo.get(Question, question.id) == nil
      assert Repo.all(from(o in QuestionOption, where: o.id in ^option_ids)) == []
    end

    test "get_quiz!/1 returns the quiz, raising when it does not exist" do
      quiz = quiz_fixture()

      assert Assessments.get_quiz!(quiz.id).id == quiz.id
      assert_raise Ecto.NoResultsError, fn -> Assessments.get_quiz!(-1) end
    end

    test "get_quiz_for_module/1 accepts a module struct or a raw id, and nil when absent" do
      module = course_module_fixture()
      quiz = quiz_fixture(%{module: module})

      assert Assessments.get_quiz_for_module(module).id == quiz.id
      assert Assessments.get_quiz_for_module(module.id).id == quiz.id
      assert Assessments.get_quiz_for_module(course_module_fixture()) == nil
    end

    test "get_quiz_with_questions!/1 preloads questions and options ordered by position" do
      quiz = quiz_fixture()

      question_fixture(%{
        quiz: quiz,
        position: 2,
        question_options: [
          %{label: "Second", correct: true, position: 2},
          %{label: "First", correct: false, position: 1}
        ]
      })

      question_fixture(%{quiz: quiz, position: 1})

      loaded = Assessments.get_quiz_with_questions!(quiz.id)

      assert Enum.map(loaded.questions, & &1.position) == [1, 2]
      second_question = Enum.find(loaded.questions, &(&1.position == 2))
      assert Enum.map(second_question.question_options, & &1.position) == [1, 2]
    end

    test "update_quiz/2 persists changed attributes" do
      quiz = quiz_fixture()

      assert {:ok, updated} = Assessments.update_quiz(quiz, %{title: "Updated title"})
      assert updated.title == "Updated title"
    end

    test "change_quiz/2 returns a changeset for the given quiz" do
      quiz = quiz_fixture()

      assert %Ecto.Changeset{data: ^quiz} = Assessments.change_quiz(quiz)
    end

    test "reorder_questions/2 safely persists a complete new order" do
      quiz = quiz_fixture()
      first = question_fixture(%{quiz: quiz, position: 1})
      second = question_fixture(%{quiz: quiz, position: 2})
      third = question_fixture(%{quiz: quiz, position: 3})

      assert {:ok, _result} =
               Assessments.reorder_questions(quiz, [third.id, first.id, second.id])

      reordered = Assessments.get_quiz_with_questions!(quiz.id).questions
      assert Enum.map(reordered, & &1.id) == [third.id, first.id, second.id]
      assert Enum.map(reordered, & &1.position) == [1, 2, 3]
    end

    test "reorder_questions/2 rejects partial or unrelated id lists" do
      quiz = quiz_fixture()
      question = question_fixture(%{quiz: quiz})
      unrelated = question_fixture()

      assert Assessments.reorder_questions(quiz, []) == {:error, :invalid_order}

      assert Assessments.reorder_questions(quiz, [question.id, unrelated.id]) ==
               {:error, :invalid_order}
    end

    test "reorder_questions/2 rejects non-integer ids" do
      quiz = quiz_fixture()
      question = question_fixture(%{quiz: quiz})

      assert Assessments.reorder_questions(quiz, ["abc"]) == {:error, :invalid_order}

      assert Assessments.reorder_questions(quiz, [question.id, "not-a-number"]) ==
               {:error, :invalid_order}
    end

    test "reorder_questions/2 rejects duplicate ids" do
      quiz = quiz_fixture()
      question = question_fixture(%{quiz: quiz})

      assert Assessments.reorder_questions(quiz, [question.id, question.id]) ==
               {:error, :invalid_order}
    end

    test "publish_quiz/1 validates completeness and activates all questions atomically" do
      quiz = quiz_fixture()

      assert Assessments.publish_quiz(quiz) ==
               {:error, {:incomplete_quiz, ["Add at least one question before publishing."]}}

      question = question_fixture(%{quiz: quiz, status: :draft})
      assert Assessments.list_published_questions(quiz) == []

      assert {:ok, published_quiz} = Assessments.publish_quiz(quiz)
      assert published_quiz.active
      assert published_quiz.published_at
      assert Enum.all?(published_quiz.questions, &(&1.status == :published))

      assert Enum.map(Assessments.list_published_questions(published_quiz), & &1.id) == [
               question.id
             ]
    end

    test "publish_quiz/1 does not mutate the quiz when completeness checks fail" do
      quiz = quiz_fixture(%{active: false})

      assert {:error, {:incomplete_quiz, _errors}} = Assessments.publish_quiz(quiz)

      reloaded = Assessments.get_quiz!(quiz.id)
      refute reloaded.active
      refute reloaded.published_at
    end

    test "count_draft_questions_by_module/1 counts drafts per module, scoped to the course" do
      course = course_fixture()
      module_with_drafts = course_module_fixture(%{course_id: course.id, position: 1})
      module_without_drafts = course_module_fixture(%{course_id: course.id, position: 2})
      other_course_module = course_module_fixture()

      quiz_a = quiz_fixture(%{module: module_with_drafts})
      question_fixture(%{quiz: quiz_a, status: :draft, position: 1})
      question_fixture(%{quiz: quiz_a, status: :draft, position: 2})
      question_fixture(%{quiz: quiz_a, status: :published, position: 3})

      quiz_b = quiz_fixture(%{module: module_without_drafts})
      question_fixture(%{quiz: quiz_b, status: :published, position: 1})

      other_quiz = quiz_fixture(%{module: other_course_module})
      question_fixture(%{quiz: other_quiz, status: :draft, position: 1})

      counts = Assessments.count_draft_questions_by_module(course.id)

      assert counts == %{module_with_drafts.id => 2}
    end
  end

  describe "questions and options" do
    test "create_question/2 with a valid option set succeeds" do
      quiz = quiz_fixture()

      assert {:ok, question} =
               Assessments.create_question(quiz, %{
                 prompt: "2 + 2?",
                 position: 1,
                 question_options: question_options_attrs()
               })

      assert length(question.question_options) == 4
      assert Enum.count(question.question_options, & &1.correct) == 1
    end

    test "create_question/2 rejects a question with zero correct options" do
      quiz = quiz_fixture()
      all_wrong = Enum.map(question_options_attrs(), &Map.put(&1, :correct, false))

      assert {:error, changeset} =
               Assessments.create_question(quiz, %{
                 prompt: "2 + 2?",
                 position: 1,
                 question_options: all_wrong
               })

      assert "must include at least one correct option" in errors_on(changeset).question_options
    end

    test "create_question/2 rejects a question with no options at all" do
      quiz = quiz_fixture()

      assert {:error, changeset} =
               Assessments.create_question(quiz, %{prompt: "2 + 2?", position: 1})

      assert %{question_options: ["can't be blank"]} = errors_on(changeset)
    end

    test "update_question/2 rejects replacing the option set with all-incorrect options" do
      question = question_fixture()
      all_wrong = Enum.map(question_options_attrs(), &Map.put(&1, :correct, false))

      assert {:error, changeset} =
               Assessments.update_question(question, %{question_options: all_wrong})

      assert "must include at least one correct option" in errors_on(changeset).question_options
    end

    test "update_question/2 can legitimately replace the whole option set" do
      question = question_fixture()

      new_options = [
        %{label: "New Right", correct: true, position: 1},
        %{label: "New Wrong", correct: false, position: 2}
      ]

      assert {:ok, updated} =
               Assessments.update_question(question, %{question_options: new_options})

      assert length(updated.question_options) == 2
      assert Enum.map(updated.question_options, & &1.label) == ["New Right", "New Wrong"]
    end

    test "positions are unique within a quiz" do
      quiz = quiz_fixture()
      question_fixture(%{quiz: quiz, position: 1})

      assert {:error, changeset} =
               Assessments.create_question(quiz, %{
                 prompt: "Another",
                 position: 1,
                 question_options: question_options_attrs()
               })

      assert "has already been used in this quiz" in errors_on(changeset).quiz_id
    end

    test "rejects a second question with the same prompt in the same quiz" do
      quiz = quiz_fixture()
      question_fixture(%{quiz: quiz, prompt: "What is the main idea?", position: 1})

      assert {:error, changeset} =
               Assessments.create_question(quiz, %{
                 prompt: "What is the main idea?",
                 position: 2,
                 question_options: question_options_attrs()
               })

      assert "already exists in this quiz" in errors_on(changeset).prompt
    end

    test "prompt uniqueness ignores case and surrounding whitespace" do
      quiz = quiz_fixture()
      question_fixture(%{quiz: quiz, prompt: "What is the main idea?", position: 1})

      assert {:error, changeset} =
               Assessments.create_question(quiz, %{
                 prompt: "  WHAT IS THE MAIN IDEA?  ",
                 position: 2,
                 question_options: question_options_attrs()
               })

      assert "already exists in this quiz" in errors_on(changeset).prompt
    end

    test "the same prompt is allowed across different quizzes" do
      quiz_a = quiz_fixture()
      quiz_b = quiz_fixture()
      question_fixture(%{quiz: quiz_a, prompt: "Shared prompt", position: 1})

      assert {:ok, _question} =
               Assessments.create_question(quiz_b, %{
                 prompt: "Shared prompt",
                 position: 1,
                 question_options: question_options_attrs()
               })
    end

    test "publish_question/1 flips a draft question to published" do
      question = question_fixture(%{status: :draft})

      assert {:ok, published} = Assessments.publish_question(question)
      assert published.status == :published
    end

    test "get_question!/1 returns the question, raising when it does not exist" do
      question = question_fixture()

      assert Assessments.get_question!(question.id).id == question.id
      assert_raise Ecto.NoResultsError, fn -> Assessments.get_question!(-1) end
    end

    test "delete_question/1 removes the question and its options" do
      question = question_fixture()
      option_ids = Enum.map(question.question_options, & &1.id)

      assert {:ok, _question} = Assessments.delete_question(question)

      assert Repo.get(Question, question.id) == nil
      assert Repo.all(from(o in QuestionOption, where: o.id in ^option_ids)) == []
    end

    test "change_question/2 returns a changeset for the given question" do
      question = question_fixture()

      assert %Ecto.Changeset{data: ^question} = Assessments.change_question(question)
    end
  end

  describe "submit_quiz/2" do
    setup do
      quiz = quiz_fixture(%{passing_score_percent: 70, active: true})

      q1 =
        question_fixture(%{
          quiz: quiz,
          position: 1,
          question_options: [
            %{label: "Right", correct: true, position: 1},
            %{label: "Wrong", correct: false, position: 2}
          ]
        })

      q2 =
        question_fixture(%{
          quiz: quiz,
          position: 2,
          question_options: [
            %{label: "Right", correct: true, position: 1},
            %{label: "Wrong", correct: false, position: 2}
          ]
        })

      %{quiz: quiz, q1: q1, q2: q2, user: user_fixture()}
    end

    test "a fully correct submission passes with a 100% score", %{
      quiz: quiz,
      q1: q1,
      q2: q2,
      user: user
    } do
      right1 = Enum.find(q1.question_options, & &1.correct)
      right2 = Enum.find(q2.question_options, & &1.correct)

      assert {:ok, submission} =
               Assessments.submit_quiz(user, quiz, %{
                 to_string(q1.id) => to_string(right1.id),
                 to_string(q2.id) => to_string(right2.id)
               })

      assert submission.score_percent == 100
      assert submission.passed
    end

    test "a fully incorrect submission fails with a 0% score", %{
      quiz: quiz,
      q1: q1,
      q2: q2,
      user: user
    } do
      wrong1 = Enum.find(q1.question_options, &(!&1.correct))
      wrong2 = Enum.find(q2.question_options, &(!&1.correct))

      assert {:ok, submission} =
               Assessments.submit_quiz(user, quiz, %{
                 to_string(q1.id) => to_string(wrong1.id),
                 to_string(q2.id) => to_string(wrong2.id)
               })

      assert submission.score_percent == 0
      refute submission.passed
    end

    test "a partial submission scores answered questions and treats unanswered ones as wrong",
         %{quiz: quiz, q1: q1, user: user} do
      right1 = Enum.find(q1.question_options, & &1.correct)

      assert {:ok, submission} =
               Assessments.submit_quiz(user, quiz, %{to_string(q1.id) => to_string(right1.id)})

      assert submission.score_percent == 50
      refute submission.passed
    end

    test "an answer referencing an unrelated option id is simply not counted as correct", %{
      quiz: quiz,
      q1: q1,
      q2: q2,
      user: user
    } do
      right2 = Enum.find(q2.question_options, & &1.correct)

      assert {:ok, submission} =
               Assessments.submit_quiz(user, quiz, %{
                 to_string(q1.id) => "999999999",
                 to_string(q2.id) => to_string(right2.id)
               })

      assert submission.score_percent == 50
    end

    test "draft questions are excluded from scoring entirely", %{
      quiz: quiz,
      q1: q1,
      q2: q2,
      user: user
    } do
      {:ok, _draft} =
        Assessments.update_question(q2, %{
          status: :draft,
          question_options: question_options_attrs()
        })

      right1 = Enum.find(q1.question_options, & &1.correct)

      assert {:ok, submission} =
               Assessments.submit_quiz(user, quiz, %{to_string(q1.id) => to_string(right1.id)})

      assert submission.score_percent == 100
    end

    test "a quiz with no published questions cannot be submitted" do
      quiz = quiz_fixture()
      user = user_fixture()

      {:ok, question} =
        Assessments.create_question(quiz, %{
          prompt: "draft only",
          position: 1,
          status: :draft,
          question_options: question_options_attrs()
        })

      assert Assessments.submit_quiz(user, quiz, %{to_string(question.id) => "1"}) ==
               {:error, :quiz_not_ready}
    end

    test "passed_quiz?/2 reflects any passing attempt, including after an earlier failure", %{
      quiz: quiz,
      q1: q1,
      q2: q2,
      user: user
    } do
      wrong1 = Enum.find(q1.question_options, &(!&1.correct))
      wrong2 = Enum.find(q2.question_options, &(!&1.correct))

      Assessments.submit_quiz(user, quiz, %{
        to_string(q1.id) => to_string(wrong1.id),
        to_string(q2.id) => to_string(wrong2.id)
      })

      refute Assessments.passed_quiz?(user, quiz)

      right1 = Enum.find(q1.question_options, & &1.correct)
      right2 = Enum.find(q2.question_options, & &1.correct)

      Assessments.submit_quiz(user, quiz, %{
        to_string(q1.id) => to_string(right1.id),
        to_string(q2.id) => to_string(right2.id)
      })

      assert Assessments.passed_quiz?(user, quiz)
    end

    test "list_submissions_for_user/2 returns only that user's attempts on that quiz, newest first",
         %{quiz: quiz, q1: q1, q2: q2, user: user} do
      right1 = Enum.find(q1.question_options, & &1.correct)
      right2 = Enum.find(q2.question_options, & &1.correct)
      wrong1 = Enum.find(q1.question_options, &(!&1.correct))

      {:ok, first} =
        Assessments.submit_quiz(user, quiz, %{to_string(q1.id) => to_string(wrong1.id)})

      {:ok, second} =
        Assessments.submit_quiz(user, quiz, %{
          to_string(q1.id) => to_string(right1.id),
          to_string(q2.id) => to_string(right2.id)
        })

      other_user = user_fixture()
      Assessments.submit_quiz(other_user, quiz, %{to_string(q1.id) => to_string(right1.id)})

      other_quiz = quiz_fixture()
      question_fixture(%{quiz: other_quiz})
      Assessments.submit_quiz(user, other_quiz, %{})

      assert Assessments.list_submissions_for_user(user, quiz) |> Enum.map(& &1.id) == [
               second.id,
               first.id
             ]
    end
  end

  describe "PDF-driven question generation" do
    test "create_generation/3 starts a pending record" do
      quiz = quiz_fixture()
      user = user_fixture()

      assert {:ok, generation} = Assessments.create_generation(quiz, user, "manual.pdf")
      assert generation.status == :pending
      assert generation.source_filename == "manual.pdf"
      assert generation.quiz_id == quiz.id
      assert generation.requested_by_id == user.id
    end

    test "list_generations_for_quiz/1 lists newest first, scoped to the quiz" do
      quiz = quiz_fixture()
      other_quiz = quiz_fixture()
      generation1 = quiz_generation_fixture(%{quiz: quiz})
      generation2 = quiz_generation_fixture(%{quiz: quiz})
      _other = quiz_generation_fixture(%{quiz: other_quiz})

      assert Enum.map(Assessments.list_generations_for_quiz(quiz), & &1.id) ==
               [generation2.id, generation1.id]
    end

    test "mark_generation_processing/1 and mark_generation_failed/2 update status" do
      generation = quiz_generation_fixture()

      processing = Assessments.mark_generation_processing(generation)
      assert processing.status == :processing

      failed = Assessments.mark_generation_failed(processing, "boom")
      assert failed.status == :failed
      assert failed.error_message == "boom"
    end

    test "mark_generation_processing/1 and mark_generation_failed/2 broadcast updates" do
      quiz = quiz_fixture()
      generation = quiz_generation_fixture(%{quiz: quiz})
      Assessments.subscribe_to_generation(quiz)

      Assessments.mark_generation_processing(generation)
      assert_receive {:quiz_generation_updated, %{status: :processing}}

      Assessments.mark_generation_failed(generation, "nope")
      assert_receive {:quiz_generation_updated, %{status: :failed, error_message: "nope"}}
    end

    test "create_draft_questions_and_mark_ready/2 inserts draft questions after existing ones and marks ready" do
      quiz = quiz_fixture()
      _existing = question_fixture(%{quiz: quiz, position: 1})
      generation = quiz_generation_fixture(%{quiz: quiz})

      drafts = [draft_question_attrs(), draft_question_attrs(%{prompt: "Second question"})]

      assert {:ok, 2} = Assessments.create_draft_questions_and_mark_ready(generation, drafts)

      quiz = Assessments.get_quiz_with_questions!(quiz.id)
      draft_questions = Enum.filter(quiz.questions, &(&1.status == :draft))
      assert length(draft_questions) == 2
      assert Enum.map(quiz.questions, & &1.position) == [1, 2, 3]

      updated = Assessments.get_generation!(generation.id)
      assert updated.status == :ready
      assert updated.questions_generated_count == 2
    end

    test "create_draft_questions_and_mark_ready/2 skips malformed drafts but keeps the valid ones" do
      quiz = quiz_fixture()
      generation = quiz_generation_fixture(%{quiz: quiz})

      all_wrong =
        draft_question_attrs(%{
          options: [
            %{label: "A", correct: false},
            %{label: "B", correct: false}
          ]
        })

      drafts = [draft_question_attrs(), all_wrong]

      assert {:ok, 1} = Assessments.create_draft_questions_and_mark_ready(generation, drafts)

      updated = Assessments.get_generation!(generation.id)
      assert updated.status == :ready
      assert updated.questions_generated_count == 1
    end

    test "create_draft_questions_and_mark_ready/2 errors when every draft is invalid" do
      quiz = quiz_fixture()
      generation = quiz_generation_fixture(%{quiz: quiz})

      all_wrong =
        draft_question_attrs(%{
          options: [%{label: "A", correct: false}, %{label: "B", correct: false}]
        })

      assert Assessments.create_draft_questions_and_mark_ready(generation, [all_wrong]) ==
               {:error, :no_valid_questions_generated}

      refute Assessments.get_generation!(generation.id).status == :ready
    end
  end

  describe "lecture quizzes" do
    test "get_lecture_quiz/1 returns nil until one exists" do
      lecture = lecture_fixture()
      assert Assessments.get_lecture_quiz(lecture.id) == nil

      quiz = lecture_quiz_fixture(lecture: lecture)
      assert Assessments.get_lecture_quiz(lecture.id).id == quiz.id
      assert Assessments.get_lecture_quiz(lecture).id == quiz.id
    end

    test "create_lecture_quiz/2 enforces one quiz per lecture" do
      lecture = lecture_fixture()
      assert {:ok, _quiz} = Assessments.create_lecture_quiz(lecture, %{title: "First"})

      assert {:error, changeset} = Assessments.create_lecture_quiz(lecture, %{title: "Second"})
      assert %{lecture_id: ["already has a quiz"]} = errors_on(changeset)
    end

    test "ensure_lecture_quiz/1 creates once, then reuses the same quiz" do
      lecture = lecture_fixture()

      assert {:ok, quiz} = Assessments.ensure_lecture_quiz(lecture)
      assert {:ok, same_quiz} = Assessments.ensure_lecture_quiz(lecture)
      assert quiz.id == same_quiz.id
    end

    test "start_lecture_quiz_generation/3 creates the quiz, the generation, and enqueues the worker" do
      lecture = lecture_fixture()
      user = user_fixture()

      assert {:ok, generation} =
               Assessments.start_lecture_quiz_generation(lecture, user, %{
                 difficulty: :easy,
                 question_count_requested: 6,
                 resource_selection: ["video"],
                 source_label: "Primary video transcript"
               })

      assert generation.status == :pending
      assert generation.difficulty == :easy
      assert generation.question_count_requested == 6
      assert Assessments.get_lecture_quiz(lecture.id) != nil

      assert_enqueued(
        worker: Wasomi.Assessments.Workers.GenerateLectureQuizWorker,
        args: %{"generation_id" => generation.id}
      )
    end

    test "start_lecture_quiz_generation/3 rejects an empty resource selection" do
      lecture = lecture_fixture()
      user = user_fixture()

      assert {:error, changeset} =
               Assessments.start_lecture_quiz_generation(lecture, user, %{
                 difficulty: :mixed,
                 question_count_requested: 10,
                 resource_selection: [],
                 source_label: "Nothing selected"
               })

      assert %{resource_selection: ["choose at least one resource"]} = errors_on(changeset)
    end

    test "get_lecture_for_generation!/1 resolves the lecture through the lecture quiz" do
      lecture = lecture_fixture()
      quiz = lecture_quiz_fixture(lecture: lecture)
      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

      assert Assessments.get_lecture_for_generation!(generation).id == lecture.id
    end

    test "mark_lecture_quiz_generation_processing/1 and _failed/2 update status and broadcast" do
      quiz = lecture_quiz_fixture()
      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)
      Assessments.subscribe_to_lecture_quiz_generation(quiz)

      processing = Assessments.mark_lecture_quiz_generation_processing(generation)
      assert processing.status == :processing
      assert_received {:lecture_quiz_generation_updated, %{status: :processing}}

      failed = Assessments.mark_lecture_quiz_generation_failed(processing, "boom")
      assert failed.status == :failed
      assert failed.error_message == "boom"
      assert_received {:lecture_quiz_generation_updated, %{status: :failed}}
    end

    test "create_lecture_quiz_draft_questions_and_mark_ready/2 inserts drafts and marks ready" do
      quiz = lecture_quiz_fixture()
      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

      assert {:ok, 1} =
               Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
                 draft_question_attrs()
               ])

      updated = Assessments.get_lecture_quiz_generation!(generation.id)
      assert updated.status == :ready
      assert updated.questions_generated_count == 1

      loaded = Assessments.get_lecture_quiz_with_questions!(quiz.id)
      assert [%{status: :draft, question_options: options}] = loaded.questions
      assert length(options) == 4
    end

    test "create_lecture_quiz_draft_questions_and_mark_ready/2 errors when every draft is invalid" do
      quiz = lecture_quiz_fixture()
      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

      all_wrong =
        draft_question_attrs(%{
          options: [%{label: "A", correct: false}, %{label: "B", correct: false}]
        })

      assert Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
               all_wrong
             ]) == {:error, :no_valid_questions_generated}

      refute Assessments.get_lecture_quiz_generation!(generation.id).status == :ready
    end

    test "publish_lecture_quiz_question/1 flips a single draft to published" do
      quiz = lecture_quiz_fixture()
      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

      {:ok, 1} =
        Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
          draft_question_attrs()
        ])

      [question] = Assessments.get_lecture_quiz_with_questions!(quiz.id).questions
      assert {:ok, published} = Assessments.publish_lecture_quiz_question(question)
      assert published.status == :published
    end

    test "publish_all_lecture_quiz_drafts/1 publishes every draft in one statement" do
      quiz = lecture_quiz_fixture()
      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

      {:ok, 2} =
        Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
          draft_question_attrs(%{prompt: "First question"}),
          draft_question_attrs(%{prompt: "Second question"})
        ])

      Assessments.publish_all_lecture_quiz_drafts(quiz)

      loaded = Assessments.get_lecture_quiz_with_questions!(quiz.id)
      assert Enum.all?(loaded.questions, &(&1.status == :published))
    end

    test "discard_all_lecture_quiz_drafts/1 deletes only draft questions" do
      quiz = lecture_quiz_fixture()
      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

      {:ok, 1} =
        Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
          draft_question_attrs()
        ])

      [question] = Assessments.get_lecture_quiz_with_questions!(quiz.id).questions
      {:ok, published} = Assessments.publish_lecture_quiz_question(question)

      {:ok, 1} =
        Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
          draft_question_attrs(%{prompt: "Another one"})
        ])

      Assessments.discard_all_lecture_quiz_drafts(quiz)

      loaded = Assessments.get_lecture_quiz_with_questions!(quiz.id)
      assert Enum.map(loaded.questions, & &1.id) == [published.id]
    end
  end

  describe "count_lecture_quiz_questions_by_lecture/1 and seed prompts for module generation" do
    test "counts are keyed by lecture id and absent for lectures with no generated quiz yet" do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id)
      with_quiz = lecture_fixture(module_id: module.id, position: 1)
      without_quiz = lecture_fixture(module_id: module.id, position: 2)

      quiz = lecture_quiz_fixture(lecture: with_quiz)
      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

      {:ok, 2} =
        Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
          draft_question_attrs(%{prompt: "First question"}),
          draft_question_attrs(%{prompt: "Second question"})
        ])

      counts = Assessments.count_lecture_quiz_questions_by_lecture(course.id)

      assert counts[with_quiz.id] == 2
      refute Map.has_key?(counts, without_quiz.id)
    end

    test "list_lecture_quiz_question_prompts_for_module/1 returns only published prompts across the module's lectures" do
      module = course_module_fixture()
      first = lecture_fixture(module_id: module.id, position: 1)
      second = lecture_fixture(module_id: module.id, position: 2)

      first_quiz = lecture_quiz_fixture(lecture: first)
      first_generation = lecture_quiz_generation_fixture(lecture_quiz: first_quiz)

      {:ok, 1} =
        Assessments.create_lecture_quiz_draft_questions_and_mark_ready(first_generation, [
          draft_question_attrs(%{prompt: "Published on lecture one"})
        ])

      Assessments.publish_all_lecture_quiz_drafts(first_quiz)

      second_quiz = lecture_quiz_fixture(lecture: second)
      second_generation = lecture_quiz_generation_fixture(lecture_quiz: second_quiz)

      {:ok, 1} =
        Assessments.create_lecture_quiz_draft_questions_and_mark_ready(second_generation, [
          draft_question_attrs(%{prompt: "Still a draft on lecture two"})
        ])

      prompts = Assessments.list_lecture_quiz_question_prompts_for_module(module.id)

      assert prompts == ["Published on lecture one"]
    end
  end

  describe "lecture_quiz_ready_for_learners?/1 and submit_lecture_quiz/3" do
    setup do
      quiz = lecture_quiz_fixture(passing_score_percent: 50)
      %{quiz: quiz, user: user_fixture()}
    end

    test "a quiz with no published questions is not ready for learners", %{quiz: quiz} do
      refute Assessments.lecture_quiz_ready_for_learners?(quiz)

      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

      {:ok, 1} =
        Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
          draft_question_attrs()
        ])

      refute Assessments.lecture_quiz_ready_for_learners?(quiz)
    end

    test "a quiz becomes ready for learners once at least one question is published", %{
      quiz: quiz
    } do
      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

      {:ok, 1} =
        Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
          draft_question_attrs()
        ])

      Assessments.publish_all_lecture_quiz_drafts(quiz)

      assert Assessments.lecture_quiz_ready_for_learners?(quiz)
    end

    test "submit_lecture_quiz/3 errors when the quiz has no published questions yet", %{
      quiz: quiz,
      user: user
    } do
      assert Assessments.submit_lecture_quiz(user, quiz, %{}) == {:error, :quiz_not_ready}
    end

    test "scores against published questions and records passed/failed correctly", %{
      quiz: quiz,
      user: user
    } do
      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

      {:ok, 2} =
        Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
          draft_question_attrs(%{prompt: "First question"}),
          draft_question_attrs(%{prompt: "Second question"})
        ])

      Assessments.publish_all_lecture_quiz_drafts(quiz)
      [q1, q2] = Assessments.list_published_lecture_quiz_questions(quiz)
      right1 = Enum.find(q1.question_options, & &1.correct)
      wrong2 = Enum.find(q2.question_options, &(!&1.correct))

      assert {:ok, submission} =
               Assessments.submit_lecture_quiz(user, quiz, %{
                 to_string(q1.id) => to_string(right1.id),
                 to_string(q2.id) => to_string(wrong2.id)
               })

      assert submission.score_percent == 50
      assert submission.passed
      assert Assessments.passed_lecture_quiz?(user, quiz)
    end

    test "passed_lecture_quiz?/2 considers any passing attempt, not just the latest", %{
      quiz: quiz,
      user: user
    } do
      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

      {:ok, 1} =
        Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
          draft_question_attrs()
        ])

      Assessments.publish_all_lecture_quiz_drafts(quiz)
      [question] = Assessments.list_published_lecture_quiz_questions(quiz)
      correct = Enum.find(question.question_options, & &1.correct)
      wrong = Enum.find(question.question_options, &(!&1.correct))

      refute Assessments.passed_lecture_quiz?(user, quiz)

      {:ok, _} = Assessments.submit_lecture_quiz(user, quiz, %{question.id => correct.id})
      assert Assessments.passed_lecture_quiz?(user, quiz)

      {:ok, _} = Assessments.submit_lecture_quiz(user, quiz, %{question.id => wrong.id})
      assert Assessments.passed_lecture_quiz?(user, quiz)
    end
  end
end
