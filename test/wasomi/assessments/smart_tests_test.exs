defmodule Wasomi.Assessments.SmartTestsTest do
  use Wasomi.DataCase, async: true

  import Mox
  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures

  alias Wasomi.Assessments
  alias Wasomi.Assessments.SmartTest

  setup :verify_on_exit!

  describe "create_smart_test/3" do
    test "creates a pending test scoped to a lecture" do
      user = user_fixture()
      module = course_module_fixture()
      lecture = lecture_fixture(module_id: module.id, position: 1)

      assert {:ok, smart_test} =
               Assessments.create_smart_test(user, lecture, %{
                 duration_minutes: 15,
                 enforce_time_limit: true,
                 multiple_choice_count: 6,
                 short_answer_count: 2,
                 difficulty: 4
               })

      assert smart_test.status == :pending
      assert smart_test.user_id == user.id
      assert smart_test.lecture_id == lecture.id
      refute smart_test.module_id
      assert SmartTest.requested_question_count(smart_test) == 8
    end

    test "rejects a test with no questions in it" do
      assert {:error, changeset} =
               Assessments.create_smart_test(user_fixture(), course_module_fixture(), %{
                 duration_minutes: 10,
                 multiple_choice_count: 0,
                 short_answer_count: 0,
                 difficulty: 3
               })

      assert "must ask for at least one question" in errors_on(changeset).multiple_choice_count
    end

    test "rejects out-of-range settings rather than clamping them" do
      assert {:error, changeset} =
               Assessments.create_smart_test(user_fixture(), course_module_fixture(), %{
                 duration_minutes: 10_000,
                 multiple_choice_count: 4,
                 short_answer_count: 0,
                 difficulty: 9
               })

      assert errors_on(changeset).duration_minutes != []
      assert errors_on(changeset).difficulty != []
    end

    test "two tests can coexist for the same learner and scope" do
      user = user_fixture()
      module = course_module_fixture()

      first = smart_test_fixture(user: user, module: module)
      second = smart_test_fixture(user: user, module: module)

      assert [latest, older] = Assessments.list_smart_tests(user, module)
      assert latest.id == second.id
      assert older.id == first.id
    end

    test "another learner's test for the same scope is invisible" do
      module = course_module_fixture()
      mine = smart_test_fixture(module: module)
      _theirs = smart_test_fixture(module: module)

      user = Wasomi.Repo.get!(Wasomi.Accounts.User, mine.user_id)

      assert [only] = Assessments.list_smart_tests(user, module)
      assert only.id == mine.id
    end
  end

  describe "mark_smart_test_ready/2" do
    test "inserts both question kinds, multiple choice first" do
      smart_test = smart_test_fixture()

      drafts = [
        draft_smart_test_written_attrs(prompt: "Written one"),
        draft_smart_test_choice_attrs(prompt: "Choice one")
      ]

      assert {:ok, 2} = Assessments.mark_smart_test_ready(smart_test, drafts)

      assert [first, second] = Assessments.list_smart_test_questions(smart_test)
      assert first.kind == :multiple_choice
      assert first.position == 1
      assert length(first.smart_test_question_options) == 4
      assert second.kind == :short_answer
      assert second.position == 2
      assert second.smart_test_question_options == []
      assert second.expected_answer

      assert %{status: :ready, questions_generated_count: 2, generated_at: %DateTime{}} =
               Assessments.get_smart_test!(smart_test.id)
    end

    test "skips malformed questions but keeps the good ones" do
      smart_test = smart_test_fixture()

      drafts = [
        draft_smart_test_choice_attrs(),
        draft_smart_test_choice_attrs(prompt: nil),
        # short answer with no model answer to score against
        draft_smart_test_written_attrs(expected_answer: nil)
      ]

      assert {:ok, 1} = Assessments.mark_smart_test_ready(smart_test, drafts)
      assert [%{kind: :multiple_choice}] = Assessments.list_smart_test_questions(smart_test)
    end

    test "fails the batch when nothing usable was generated" do
      smart_test = smart_test_fixture()

      assert {:error, :no_valid_questions_generated} =
               Assessments.mark_smart_test_ready(smart_test, [
                 draft_smart_test_choice_attrs(prompt: nil)
               ])
    end

    test "broadcasts to a subscriber so an open test appears without polling" do
      smart_test = smart_test_fixture()
      Assessments.subscribe_to_smart_test(smart_test)

      Assessments.mark_smart_test_processing(smart_test)
      assert_receive {:smart_test_updated, %{status: :processing}}

      Assessments.mark_smart_test_ready(smart_test, [draft_smart_test_choice_attrs()])
      assert_receive {:smart_test_updated, %{status: :ready}}
    end
  end

  describe "the attempt clock" do
    test "start_smart_test/1 persists a deadline derived from the chosen duration" do
      smart_test = smart_test_fixture(duration_minutes: 10)

      assert {:ok, started} = Assessments.start_smart_test(smart_test)
      assert started.started_at
      assert_in_delta DateTime.diff(started.expires_at, started.started_at), 600, 2
      assert_in_delta Assessments.smart_test_remaining_seconds(started), 600, 2
    end

    test "a test with the time limit switched off has no deadline at all" do
      smart_test = smart_test_fixture(enforce_time_limit: false)

      assert {:ok, started} = Assessments.start_smart_test(smart_test)
      refute started.expires_at
      refute Assessments.smart_test_remaining_seconds(started)
    end

    test "pausing freezes the remaining time and resuming pushes the deadline out" do
      smart_test = smart_test_fixture(duration_minutes: 10)
      {:ok, started} = Assessments.start_smart_test(smart_test)

      {:ok, paused} = Assessments.pause_smart_test(started)
      frozen = Assessments.smart_test_remaining_seconds(paused)

      # Rewinding the recorded pause instant stands in for wall-clock time
      # passing while paused.
      paused = %{paused | paused_at: DateTime.add(paused.paused_at, -30, :second)}

      assert Assessments.smart_test_remaining_seconds(paused) == frozen + 30

      {:ok, resumed} = Assessments.resume_smart_test(paused)
      refute resumed.paused_at
      assert_in_delta Assessments.smart_test_remaining_seconds(resumed), frozen + 30, 2
    end

    test "remaining time never goes negative once the deadline has passed" do
      smart_test = smart_test_fixture()
      {:ok, started} = Assessments.start_smart_test(smart_test)
      expired = %{started | expires_at: DateTime.add(DateTime.utc_now(), -60, :second)}

      assert Assessments.smart_test_remaining_seconds(expired) == 0
    end
  end

  describe "answering and scoring" do
    setup do
      smart_test = ready_smart_test_fixture()
      [choice, written] = smart_test.smart_test_questions

      %{smart_test: smart_test, choice: choice, written: written}
    end

    test "an option from another question is rejected", %{choice: choice} do
      other = ready_smart_test_fixture()
      [other_choice | _] = other.smart_test_questions
      [foreign_option | _] = other_choice.smart_test_question_options

      assert {:error, :unknown_option} =
               Assessments.record_smart_test_answer(choice, foreign_option.id)
    end

    test "a correct multiple choice answer scores 100%", %{
      smart_test: smart_test,
      choice: choice,
      written: written
    } do
      correct = Enum.find(choice.smart_test_question_options, & &1.correct)
      {:ok, _} = Assessments.record_smart_test_answer(choice, correct.id)
      {:ok, _} = Assessments.record_smart_test_answer(written, "The parts work together.")

      expect(Wasomi.LectureQuestionScorerMock, :score, fn prompt, model_answer, learner_answer ->
        assert prompt == written.prompt
        assert model_answer == written.expected_answer
        assert learner_answer == "The parts work together."
        {:ok, 1.0}
      end)

      assert {:ok, finished} = Assessments.finish_smart_test(smart_test)
      assert finished.score_percent == 100
      assert finished.completed_at
      refute finished.time_expired
    end

    test "short answers are graded on how well they match the model answer", %{
      smart_test: smart_test,
      choice: choice,
      written: written
    } do
      wrong = Enum.find(choice.smart_test_question_options, &(!&1.correct))
      {:ok, _} = Assessments.record_smart_test_answer(choice, wrong.id)
      {:ok, _} = Assessments.record_smart_test_answer(written, "Something roughly right.")

      expect(Wasomi.LectureQuestionScorerMock, :score, fn _, _, _ -> {:ok, 0.6} end)

      assert {:ok, finished} = Assessments.finish_smart_test(smart_test)
      # (0.0 + 0.6) / 2
      assert finished.score_percent == 30

      graded = Assessments.list_smart_test_questions(finished)
      assert Enum.map(graded, & &1.score) == [0.0, 0.6]
      refute Assessments.smart_test_question_correct?(Enum.at(graded, 0))
      assert Assessments.smart_test_question_correct?(Enum.at(graded, 1))
    end

    test "an unanswered short answer scores zero without calling the scorer", %{
      smart_test: smart_test
    } do
      # No `expect` for the scorer: a blank answer must never reach it.
      assert {:ok, finished} = Assessments.finish_smart_test(smart_test, time_expired: true)
      assert finished.score_percent == 0
      assert finished.time_expired
    end

    test "a scorer failure leaves that question ungraded and out of the percentage", %{
      smart_test: smart_test,
      choice: choice,
      written: written
    } do
      correct = Enum.find(choice.smart_test_question_options, & &1.correct)
      {:ok, _} = Assessments.record_smart_test_answer(choice, correct.id)
      {:ok, _} = Assessments.record_smart_test_answer(written, "An answer.")

      expect(Wasomi.LectureQuestionScorerMock, :score, fn _, _, _ -> {:error, :boom} end)

      assert {:ok, finished} = Assessments.finish_smart_test(smart_test)
      # Scored on the one question that could be graded, not marked wrong.
      assert finished.score_percent == 100
      assert [%{score: 1.0}, %{score: nil}] = Assessments.list_smart_test_questions(finished)
    end

    test "reset_smart_test/1 clears answers and scores but keeps the questions", %{
      smart_test: smart_test,
      choice: choice
    } do
      correct = Enum.find(choice.smart_test_question_options, & &1.correct)
      {:ok, _} = Assessments.record_smart_test_answer(choice, correct.id)
      {:ok, started} = Assessments.start_smart_test(smart_test)

      expect(Wasomi.LectureQuestionScorerMock, :score, 0, fn _, _, _ -> {:ok, 1.0} end)
      {:ok, finished} = Assessments.finish_smart_test(started)

      assert {:ok, reset} = Assessments.reset_smart_test(finished)
      refute reset.completed_at
      refute reset.started_at
      refute reset.score_percent

      assert [first, second] = Assessments.list_smart_test_questions(reset)
      assert length(first.smart_test_question_options) == 4
      assert Enum.all?([first, second], &(is_nil(&1.score) and is_nil(&1.response_option_id)))
      assert Enum.all?([first, second], &is_nil(&1.response_text))
    end
  end

  describe "latest_smart_test/2" do
    test "returns the most recent test with its questions loaded" do
      user = user_fixture()
      module = course_module_fixture()
      _older = smart_test_fixture(user: user, module: module)
      newest = ready_smart_test_fixture(user: user, module: module)

      latest = Assessments.latest_smart_test(user, module)

      assert latest.id == newest.id
      assert [%{kind: :multiple_choice}, %{kind: :short_answer}] = latest.smart_test_questions
    end

    test "is nil before the learner has built anything" do
      refute Assessments.latest_smart_test(user_fixture(), course_module_fixture())
    end
  end
end
