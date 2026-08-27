defmodule WasomiWeb.StudyHubLiveTest do
  use WasomiWeb.ConnCase
  use Oban.Testing, repo: Wasomi.Repo

  import Phoenix.LiveViewTest
  import Mox
  import Wasomi.CatalogFixtures
  import Wasomi.AssessmentsFixtures

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Workers.GenerateFlashcardsWorker
  alias Wasomi.Assessments.Workers.GeneratePracticeSetQuestionsWorker
  alias Wasomi.Assessments.Workers.GenerateSmartTestWorker
  alias Wasomi.Assessments.Workers.GenerateStudyGuideWorker
  alias Wasomi.Enrollments

  setup :register_and_log_in_user
  setup :verify_on_exit!

  defp enroll!(user, course) do
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, active} = Enrollments.activate_enrollment(pending)
    active
  end

  describe "capture protection" do
    test "the hub is guarded and watermarked with the viewer's identity", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/learn/study")

      assert has_element?(
               view,
               "#study-hub[phx-hook='CaptureGuard'][data-watermark='User ##{user.id}']"
             )

      refute has_element?(view, "#study-hub[data-watermark*='#{user.email}']")
    end

    test "a reported capture attempt is logged", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/learn/study")

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert render_hook(view, "capture-attempt", %{"kind" => "copy"})
        end)

      assert log =~ "capture attempt: kind=copy user_id=#{user.id} surface=study_hub"
    end
  end

  describe "embedded study" do
    test "uses the course page chrome and preserves it while choosing a flashcard scope", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, mode: "flashcards", embedded: true}}"
        )

      refute has_element?(view, "#student-sidebar")
      assert has_element?(view, "h2", "Study the whole module, or one lesson?")

      view |> element("button[phx-value-scope='module']") |> render_click()

      refute has_element?(view, "#student-sidebar")
      assert render(view) =~ "Build your flashcards"
    end
  end

  describe "course picker" do
    test "shows an empty state with no active enrollments", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/learn/study")
      assert has_element?(view, "h2", "Choose a course")
      assert render(view) =~ "don&#39;t have any active enrollments"
    end

    test "lists every actively-enrolled course when there is more than one", %{
      conn: conn,
      user: user
    } do
      course1 = course_fixture(status: :published, title: "Elixir Basics")
      course2 = course_fixture(status: :published, title: "Advanced OTP")
      enroll!(user, course1)
      enroll!(user, course2)

      {:ok, view, _html} = live(conn, ~p"/learn/study")

      assert has_element?(view, "button[phx-value-slug='#{course1.slug}']", "Elixir Basics")
      assert has_element?(view, "button[phx-value-slug='#{course2.slug}']", "Advanced OTP")
    end

    test "a pending (unpaid) enrollment is not offered", %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      {:ok, _pending} = Enrollments.create_pending_enrollment(user, course)

      {:ok, view, _html} = live(conn, ~p"/learn/study")
      assert render(view) =~ "don&#39;t have any active enrollments"
    end

    test "a single active enrollment is auto-selected", %{conn: conn, user: user} do
      course = course_fixture(status: :published, title: "Solo Course")
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      {:ok, view, _html} = live(conn, ~p"/learn/study")

      refute has_element?(view, "h2", "Choose a course")
      refute has_element?(view, "button[phx-value-slug]")
    end
  end

  describe "module picker" do
    test "lists every module in the chosen course", %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module1 = course_module_fixture(course_id: course.id, position: 1, title: "Module One")
      lecture_fixture(module_id: module1.id, position: 1)
      module2 = course_module_fixture(course_id: course.id, position: 2, title: "Module Two")
      lecture_fixture(module_id: module2.id, position: 1)
      enroll!(user, course)

      {:ok, view, _html} = live(conn, ~p"/learn/study?#{%{course: course.slug}}")

      assert has_element?(view, "button[phx-value-module_id='#{module1.id}']", "Module One")
      assert has_element?(view, "button[phx-value-module_id='#{module2.id}']", "Module Two")
    end

    test "a single-module course is auto-selected", %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      {:ok, view, _html} = live(conn, ~p"/learn/study?#{%{course: course.slug}}")

      refute has_element?(view, "h2", "Choose a module")
    end

    test "an unknown module id in the URL falls back to the module picker", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module1 = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module1.id, position: 1)
      module2 = course_module_fixture(course_id: course.id, position: 2)
      lecture_fixture(module_id: module2.id, position: 1)
      enroll!(user, course)

      {:ok, view, _html} =
        live(conn, ~p"/learn/study?#{%{course: course.slug, module: 999_999}}")

      assert has_element?(view, "h2", "Choose a module")
    end
  end

  describe "scope picker (whole module vs. one lesson)" do
    test "offers the whole module plus every lecture, and is not auto-skipped for a single lecture",
         %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1, title: "Only Lesson")
      enroll!(user, course)

      {:ok, view, _html} =
        live(conn, ~p"/learn/study?#{%{course: course.slug, module: module.id}}")

      assert has_element?(view, "h2", "Study the whole module, or one lesson?")
      assert has_element?(view, "button[phx-value-scope='module']", "Whole module")

      assert has_element?(
               view,
               "button[phx-value-scope='lecture'][phx-value-lecture_id='#{lecture.id}']",
               "Only Lesson"
             )
    end

    test "picking a lecture scopes subsequent steps to that lecture", %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      {:ok, view, _html} =
        live(conn, ~p"/learn/study?#{%{course: course.slug, module: module.id}}")

      html =
        view
        |> element("button[phx-value-scope='lecture'][phx-value-lecture_id='#{lecture.id}']")
        |> render_click()

      assert html =~ "What do you want to do?"
      assert html =~ "Smart Test"
    end
  end

  describe "mode picker" do
    test "offers Study guide, Flashcards, Extra practice, and Smart Test for a whole-module scope",
         %{
           conn: conn,
           user: user
         } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module"}}"
        )

      assert has_element?(view, "button[phx-value-mode='study_guide']", "Study guide")
      assert has_element?(view, "button[phx-value-mode='flashcards']", "Flashcards")
      assert has_element?(view, "button[phx-value-mode='practice']", "Extra practice")
      assert has_element?(view, "button[phx-value-mode='timed_quiz']", "Smart Test")
    end

    test "offers Smart Test for a single-lecture scope too", %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "lecture", lecture: lecture.id}}"
        )

      assert has_element?(view, "button[phx-value-mode='flashcards']")
      assert has_element?(view, "button[phx-value-mode='timed_quiz']", "Smart Test")
    end

    test "a lecture-scoped Smart Test URL opens the builder for that lesson",
         %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1, title: "How GS1 works")
      enroll!(user, course)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "lecture", lecture: lecture.id, mode: "timed_quiz"}}"
        )

      assert html =~ "Smart Test"
      assert html =~ "How GS1 works"
      assert html =~ "Create test"
    end
  end

  describe "Flashcards content" do
    test "first visit creates a pending set and waits for the learner to ask", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "flashcards"}}"
        )

      assert html =~ "Build your flashcards"
      refute html =~ "Generating your flashcards"
      {:ok, set} = Assessments.get_or_create_flashcard_set(module)
      assert set.status == :pending
      refute_enqueued(worker: GenerateFlashcardsWorker, args: %{"flashcard_set_id" => set.id})
    end

    test "the setup panel generates on request and offers the module's lectures as scopes", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1, title: "Barcodes 101")
      enroll!(user, course)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "flashcards"}}"
        )

      # Re-pointing at a single lesson keeps the learner in Flashcards rather
      # than dropping them back on the mode picker.
      html =
        view
        |> element("button[phx-value-scope='lecture'][phx-value-lecture_id='#{lecture.id}']")
        |> render_click()

      assert html =~ "Barcodes 101"
      assert html =~ "Build your flashcards"

      html = view |> element("button", "Generate flashcards") |> render_click()
      assert html =~ "Generating your flashcards"

      {:ok, lecture_set} = Assessments.get_or_create_flashcard_set(lecture)
      assert lecture_set.status == :processing

      assert_enqueued(
        worker: GenerateFlashcardsWorker,
        args: %{"flashcard_set_id" => lecture_set.id}
      )

      # The whole-module set is untouched — only the scope they asked for is generated.
      {:ok, module_set} = Assessments.get_or_create_flashcard_set(module)
      assert module_set.status == :pending

      refute_enqueued(
        worker: GenerateFlashcardsWorker,
        args: %{"flashcard_set_id" => module_set.id}
      )
    end

    test "a ready set shows the review UI and rating persists progress", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      set = flashcard_set_fixture(module: module)

      {:ok, 1} =
        Assessments.mark_flashcard_set_ready(set, [
          draft_flashcard_attrs(%{front: "What is OTP?", back: "Open Telecom Platform"})
        ])

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "flashcards"}}"
        )

      assert render(view) =~ "What is OTP?"

      html = view |> element("button[phx-value-rating='known']") |> render_click()
      assert html =~ "Deck complete!"

      [card] = Assessments.list_flashcards(set)

      assert %{status: :known} =
               Wasomi.Repo.get_by!(Assessments.FlashcardProgress,
                 flashcard_id: card.id,
                 user_id: user.id
               )
    end

    test "a lecture-scoped set is independent from that module's whole-module set", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      lecture_set = flashcard_set_fixture(lecture: lecture)
      {:ok, 1} = Assessments.mark_flashcard_set_ready(lecture_set, [draft_flashcard_attrs()])

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "lecture", lecture: lecture.id, mode: "flashcards"}}"
        )

      assert render(view) =~ "Card 1 of 1"

      {:ok, module_set} = Assessments.get_or_create_flashcard_set(module)
      assert module_set.status == :pending
      assert module_set.id != lecture_set.id
    end

    test "a failed set shows a retry action that re-enqueues generation", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      set = flashcard_set_fixture(module: module)
      Assessments.mark_flashcard_set_failed(set, "no resources")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "flashcards"}}"
        )

      assert has_element?(view, "button", "Try again")
      view |> element("button", "Try again") |> render_click()

      assert_enqueued(worker: GenerateFlashcardsWorker, args: %{"flashcard_set_id" => set.id})
    end

    test "the deck reports its status breakdown and where the cards came from", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      set = flashcard_set_fixture(module: module)

      {:ok, 2} =
        Assessments.mark_flashcard_set_ready(
          set,
          [
            draft_flashcard_attrs(%{front: "Card one"}),
            draft_flashcard_attrs(%{front: "Card two"})
          ],
          source: :practice_questions
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "flashcards"}}"
        )

      html = render(view)
      assert html =~ "2 cards"
      assert html =~ "practice questions"
      assert html =~ "Reviewing"
      assert html =~ "Mastered"
    end

    test "rating a card Easy marks it mastered", %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      set = flashcard_set_fixture(module: module)
      {:ok, 1} = Assessments.mark_flashcard_set_ready(set, [draft_flashcard_attrs()])

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "flashcards"}}"
        )

      view |> element("button[phx-value-rating='mastered']") |> render_click()

      [card] = Assessments.list_flashcards(set)

      assert %{status: :mastered} =
               Wasomi.Repo.get_by!(Assessments.FlashcardProgress,
                 flashcard_id: card.id,
                 user_id: user.id
               )
    end

    test "generating a new deck clears the old cards and re-enqueues generation", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      set = flashcard_set_fixture(module: module)

      {:ok, 1} =
        Assessments.mark_flashcard_set_ready(set, [draft_flashcard_attrs(%{front: "Stale card"})])

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "flashcards"}}"
        )

      html = view |> element("button", "Generate a new deck") |> render_click()

      assert html =~ "Generating your flashcards"
      refute html =~ "Stale card"
      assert Assessments.list_flashcards(set) == []
      assert Assessments.get_flashcard_set!(set.id).status == :processing
      assert_enqueued(worker: GenerateFlashcardsWorker, args: %{"flashcard_set_id" => set.id})
    end
  end

  describe "Extra practice content" do
    test "first visit creates a pending quiz and enqueues generation", %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "practice"}}"
        )

      assert html =~ "Generating extra practice questions"
      {:ok, quiz} = Assessments.get_or_create_practice_set(module)
      assert quiz.status == :pending

      assert_enqueued(
        worker: GeneratePracticeSetQuestionsWorker,
        args: %{"practice_set_id" => quiz.id}
      )
    end

    test "answering a question shows immediate feedback and persists progress", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      quiz = practice_set_fixture(module: module)
      {:ok, 1} = Assessments.mark_practice_set_ready(quiz, [draft_question_attrs()])

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "practice"}}"
        )

      [question] = Assessments.list_practice_set_questions(quiz)
      correct = Enum.find(question.practice_set_question_options, & &1.correct)

      html =
        view
        |> element("button[phx-value-option-id='#{correct.id}']")
        |> render_click()

      assert html =~ "Correct!"

      assert %{last_correct: true} =
               Wasomi.Repo.get_by!(Assessments.PracticeSetQuestionProgress,
                 practice_set_question_id: question.id,
                 user_id: user.id
               )
    end
  end

  defp smart_test_path(course, module) do
    ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "timed_quiz"}}"
  end

  describe "Smart Test content" do
    setup %{user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1, title: "How GS1 works")
      enroll!(user, course)

      %{course: course, module: module, lecture: lecture}
    end

    test "opens on the settings form with defaults, and no test to resume yet", %{
      conn: conn,
      course: course,
      module: module
    } do
      {:ok, view, html} = live(conn, smart_test_path(course, module))

      assert html =~ "Smart Test"
      assert html =~ "10 min"
      assert html =~ "8 questions"
      assert html =~ "10 minute limit"
      refute html =~ "Saved test"
      assert has_element?(view, "button", "Create test")
    end

    test "the duration stepper and question counts drive the summary", %{
      conn: conn,
      course: course,
      module: module
    } do
      {:ok, view, _html} = live(conn, smart_test_path(course, module))

      html = view |> element("button[phx-value-by='5']") |> render_click()
      assert html =~ "15 min"

      html =
        view
        |> element("form[phx-submit='create-smart-test']")
        |> render_change(%{
          "settings" => %{
            "duration_minutes" => "15",
            "enforce_time_limit" => "false",
            "multiple_choice_count" => "4",
            "short_answer_count" => "1",
            "difficulty" => "5"
          }
        })

      assert html =~ "5 questions"
      assert html =~ "5 of 5"
      # Explicitly unchecked (not just omitted — render_change on a <form>
      # element reads the checkbox's current DOM state for any key it isn't
      # told, so leaving this out would keep whatever was last checked).
      assert html =~ "No time limit"
    end

    test "settings are clamped rather than trusted", %{conn: conn, course: course, module: module} do
      {:ok, view, _html} = live(conn, smart_test_path(course, module))

      html =
        view
        |> element("form[phx-submit='create-smart-test']")
        |> render_change(%{
          "settings" => %{
            "duration_minutes" => "9999",
            "multiple_choice_count" => "999",
            "short_answer_count" => "0",
            "difficulty" => "99"
          }
        })

      assert html =~ "180 min"
      assert html =~ "20 questions"
      assert html =~ "5 of 5"
    end

    test "creating a test enqueues generation and shows the building state", %{
      conn: conn,
      user: user,
      course: course,
      module: module
    } do
      {:ok, view, _html} = live(conn, smart_test_path(course, module))

      html = view |> element("form[phx-submit='create-smart-test']") |> render_submit()

      assert html =~ "Building your Smart Test"

      [smart_test] = Assessments.list_smart_tests(user, module)
      assert smart_test.status == :pending
      assert smart_test.multiple_choice_count == 6
      assert smart_test.short_answer_count == 2

      assert_enqueued(
        worker: GenerateSmartTestWorker,
        args: %{"smart_test_id" => smart_test.id}
      )
    end

    test "generation finishing swaps the building state for the launchpad", %{
      conn: conn,
      user: user,
      course: course,
      module: module
    } do
      {:ok, view, _html} = live(conn, smart_test_path(course, module))
      view |> element("form[phx-submit='create-smart-test']") |> render_submit()

      [smart_test] = Assessments.list_smart_tests(user, module)

      {:ok, _count} =
        Assessments.mark_smart_test_ready(smart_test, [
          draft_smart_test_choice_attrs(prompt: "Which is true?"),
          draft_smart_test_written_attrs(prompt: "Explain it.")
        ])

      html = render(view)
      assert html =~ "Your Smart Test is ready"
      assert has_element?(view, "button", "Start your test")
    end

    test "a saved test can be resumed from the settings screen", %{
      conn: conn,
      user: user,
      module: module,
      course: course
    } do
      ready_smart_test_fixture(user: user, module: module, difficulty: 4)

      {:ok, view, html} = live(conn, smart_test_path(course, module))

      assert html =~ "Saved test"
      assert html =~ "Not started"
      assert html =~ "4 of 5"

      html = view |> element("button[phx-click='open-smart-test']") |> render_click()
      assert html =~ "Your Smart Test is ready"
    end

    test "starting the test shows every question, keeps answers, and scores on finish", %{
      conn: conn,
      user: user,
      module: module,
      course: course
    } do
      smart_test = ready_smart_test_fixture(user: user, module: module)
      [choice, written] = smart_test.smart_test_questions
      correct = Enum.find(choice.smart_test_question_options, & &1.correct)

      {:ok, view, _html} = live(conn, smart_test_path(course, module))
      view |> element("button[phx-click='open-smart-test']") |> render_click()
      html = view |> element("button", "Start your test") |> render_click()

      assert html =~ "Complete every question, then check your score."
      assert html =~ choice.prompt
      assert html =~ written.prompt
      assert has_element?(view, "#smart-test-countdown")

      view
      |> element("button[phx-value-option-id='#{correct.id}']")
      |> render_click()

      view
      |> element("form[phx-change='answer-smart-test-text']")
      |> render_change(%{"question_id" => written.id, "response" => "They work together."})

      # Answers are persisted as they're given, not gathered at submit time.
      assert [%{response_option_id: option_id}, %{response_text: "They work together."}] =
               Assessments.list_smart_test_questions(smart_test)

      assert option_id == correct.id

      expect(Wasomi.LectureQuestionScorerMock, :score, fn _, _, _ -> {:ok, 1.0} end)

      html = view |> element("#finish-smart-test-top") |> render_click()

      assert html =~ "Test complete"
      assert html =~ "100%"
      assert html =~ "Model answer"
      assert Assessments.get_smart_test!(smart_test.id).score_percent == 100
    end

    test "leaving for the settings screen pauses the clock", %{
      conn: conn,
      user: user,
      module: module,
      course: course
    } do
      smart_test = ready_smart_test_fixture(user: user, module: module)

      {:ok, view, _html} = live(conn, smart_test_path(course, module))
      view |> element("button[phx-click='open-smart-test']") |> render_click()
      view |> element("button", "Start your test") |> render_click()

      html = view |> element("button", "Test settings") |> render_click()

      assert html =~ "Paused"
      assert Assessments.get_smart_test!(smart_test.id).paused_at

      html = view |> element("button[phx-click='open-smart-test']") |> render_click()
      assert html =~ "Test paused"

      html = view |> element("button", "Resume your test") |> render_click()
      assert html =~ "Complete every question, then check your score."
      refute Assessments.get_smart_test!(smart_test.id).paused_at
    end

    test "the deadline expiring scores whatever was answered", %{
      conn: conn,
      user: user,
      module: module,
      course: course
    } do
      smart_test = ready_smart_test_fixture(user: user, module: module)

      {:ok, view, _html} = live(conn, smart_test_path(course, module))
      view |> element("button[phx-click='open-smart-test']") |> render_click()
      view |> element("button", "Start your test") |> render_click()

      send(view.pid, :smart_test_expired)
      html = render(view)

      assert html =~ "Time&#39;s up!"

      finished = Assessments.get_smart_test!(smart_test.id)
      assert finished.time_expired
      assert finished.score_percent == 0
    end

    test "an answer arriving after the test is scored is ignored", %{
      conn: conn,
      user: user,
      module: module,
      course: course
    } do
      smart_test = ready_smart_test_fixture(user: user, module: module)
      [choice, _written] = smart_test.smart_test_questions
      correct = Enum.find(choice.smart_test_question_options, & &1.correct)

      {:ok, view, _html} = live(conn, smart_test_path(course, module))
      view |> element("button[phx-click='open-smart-test']") |> render_click()
      view |> element("button", "Start your test") |> render_click()

      send(view.pid, :smart_test_expired)
      render(view)

      render_click(view, "answer-smart-test-choice", %{
        "question-id" => choice.id,
        "option-id" => correct.id
      })

      assert [%{response_option_id: nil, score: 0.0} | _] =
               Assessments.list_smart_test_questions(smart_test)
    end

    test "a retake clears the previous attempt but keeps the questions", %{
      conn: conn,
      user: user,
      module: module,
      course: course
    } do
      smart_test = ready_smart_test_fixture(user: user, module: module)

      {:ok, view, _html} = live(conn, smart_test_path(course, module))
      view |> element("button[phx-click='open-smart-test']") |> render_click()
      view |> element("button", "Start your test") |> render_click()
      view |> element("#finish-smart-test-top") |> render_click()

      html = view |> element("button", "Retake this test") |> render_click()

      assert html =~ "Your Smart Test is ready"
      reset = Assessments.get_smart_test!(smart_test.id)
      refute reset.score_percent
      assert length(Assessments.list_smart_test_questions(reset)) == 2
    end

    test "a failed generation offers a retry", %{
      conn: conn,
      user: user,
      module: module,
      course: course
    } do
      smart_test = smart_test_fixture(user: user, module: module)
      Assessments.mark_smart_test_failed(smart_test, "no_resources_available")

      {:ok, view, _html} = live(conn, smart_test_path(course, module))
      html = view |> element("button[phx-click='open-smart-test']") |> render_click()

      assert html =~ "We couldn&#39;t build this Smart Test."

      view |> element("button", "Try again") |> render_click()

      assert_enqueued(
        worker: GenerateSmartTestWorker,
        args: %{"smart_test_id" => smart_test.id}
      )
    end
  end

  defp study_guide_path(course, module) do
    ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "study_guide"}}"
  end

  describe "Study guide content" do
    setup %{user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1, title: "Barcode basics")
      lecture = lecture_fixture(module_id: module.id, position: 1, title: "How GS1 works")
      enroll!(user, course)

      %{course: course, module: module, lecture: lecture}
    end

    test "opens on the brief, with the styles to choose from and nothing generated yet", %{
      conn: conn,
      course: course,
      module: module
    } do
      {:ok, view, html} = live(conn, study_guide_path(course, module))

      assert html =~ "Study guide"
      assert html =~ "Short notes"
      assert html =~ "As a story"
      assert html =~ "Cheat sheet"
      assert html =~ "By analogy"
      refute html =~ "Your guides"
      assert has_element?(view, "button", "Write my study guide")
    end

    test "the brief reflects the style, depth, level and focus the learner picks", %{
      conn: conn,
      course: course,
      module: module
    } do
      {:ok, view, _html} = live(conn, study_guide_path(course, module))

      view
      |> element("form[phx-submit='create-study-guide']")
      |> render_change(%{
        "settings" => %{
          "style" => "story",
          "depth" => "deep",
          "reading_level" => "beginner",
          "focus" => "check digits only"
        }
      })

      assert has_element?(view, "input[name='settings[style]'][value='story'][checked]")
      assert has_element?(view, "input[name='settings[depth]'][value='deep'][checked]")

      assert has_element?(
               view,
               "input[name='settings[reading_level]'][value='beginner'][checked]"
             )

      refute has_element?(view, "input[name='settings[style]'][value='notes'][checked]")
      assert render(view) =~ "check digits only"
    end

    test "a hand-edited style is ignored rather than trusted", %{
      conn: conn,
      user: user,
      course: course,
      module: module
    } do
      {:ok, view, _html} = live(conn, study_guide_path(course, module))

      view
      |> element("form[phx-submit='create-study-guide']")
      |> render_change(%{"settings" => %{"style" => "limerick", "depth" => "nope"}})

      view |> element("form[phx-submit='create-study-guide']") |> render_submit()

      [guide] = Assessments.list_study_guides(user, module)
      assert guide.style == :notes
      assert guide.depth == :standard
    end

    test "asking for a guide enqueues generation and shows the writing state", %{
      conn: conn,
      user: user,
      course: course,
      module: module
    } do
      {:ok, view, _html} = live(conn, study_guide_path(course, module))

      html =
        view
        |> element("form[phx-submit='create-study-guide']")
        |> render_submit(%{
          "settings" => %{
            "style" => "story",
            "depth" => "brief",
            "reading_level" => "intermediate",
            "include_examples" => "true",
            "include_key_terms" => "false",
            "focus" => "  check digits  "
          }
        })

      assert html =~ "Writing your study guide"

      [guide] = Assessments.list_study_guides(user, module)
      assert guide.status == :pending
      assert guide.style == :story
      assert guide.depth == :brief
      assert guide.include_examples
      refute guide.include_key_terms
      assert guide.focus == "check digits"

      assert_enqueued(worker: GenerateStudyGuideWorker, args: %{"study_guide_id" => guide.id})
    end

    test "generation finishing swaps the writing state for the document", %{
      conn: conn,
      user: user,
      course: course,
      module: module
    } do
      {:ok, view, _html} = live(conn, study_guide_path(course, module))
      view |> element("form[phx-submit='create-study-guide']") |> render_submit()

      [guide] = Assessments.list_study_guides(user, module)
      {:ok, 2} = Assessments.mark_study_guide_ready(guide, draft_study_guide_attrs())

      html = render(view)
      assert html =~ "How GS1 barcodes identify a product"
      assert html =~ "The gist"
      assert html =~ "Where the number comes from"
      # Body prose is split into paragraphs by us, not by the model's markup.
      assert html =~ "A prefix identifies the company."
      assert html =~ "The item number is yours to assign."
      assert html =~ "The prefix is issued by GS1"
      assert html =~ "Key idea:"
      assert html =~ "Key terms"
      assert html =~ "GTIN"
      assert html =~ "Before you move on"
    end

    test "a failed generation offers a retry", %{
      conn: conn,
      user: user,
      course: course,
      module: module
    } do
      {:ok, view, _html} = live(conn, study_guide_path(course, module))
      view |> element("form[phx-submit='create-study-guide']") |> render_submit()

      [guide] = Assessments.list_study_guides(user, module)
      Assessments.mark_study_guide_failed(guide, "boom")

      assert render(view) =~ "write this study guide"

      view |> element("button", "Try again") |> render_click()
      assert_enqueued(worker: GenerateStudyGuideWorker, args: %{"study_guide_id" => guide.id})
    end

    test "landing on a scope with a finished guide opens the document, not the brief", %{
      conn: conn,
      user: user,
      course: course,
      module: module
    } do
      ready_study_guide_fixture(user: user, module: module, style: :cheat_sheet)

      {:ok, view, html} = live(conn, study_guide_path(course, module))

      assert html =~ "How GS1 barcodes identify a product"
      assert has_element?(view, "button", "Guide settings")

      html = view |> element("button", "Guide settings") |> render_click()
      assert html =~ "Your guides"
      assert html =~ "Write my study guide"
    end

    test "saved guides can be reopened and deleted", %{
      conn: conn,
      user: user,
      course: course,
      module: module
    } do
      guide = ready_study_guide_fixture(user: user, module: module, style: :story)

      {:ok, view, _html} = live(conn, study_guide_path(course, module))
      view |> element("button", "Guide settings") |> render_click()

      html = view |> element("button[phx-click='open-study-guide']") |> render_click()
      assert html =~ "How GS1 barcodes identify a product"

      view |> element("button", "Guide settings") |> render_click()
      html = view |> element("button[phx-click='delete-study-guide']") |> render_click()

      refute html =~ "Your guides"
      assert Assessments.list_study_guides(user, module) == []
      refute Assessments.get_user_study_guide(user, guide.id)
    end

    test "another learner's guide id can't be opened", %{
      conn: conn,
      course: course,
      module: module
    } do
      other_guide = ready_study_guide_fixture(module: module)

      {:ok, view, _html} = live(conn, study_guide_path(course, module))

      assert render_click(view, "open-study-guide", %{"id" => to_string(other_guide.id)})
      refute render(view) =~ "How GS1 barcodes identify a product"
    end

    test "a lecture-scoped guide is titled for that lesson", %{
      conn: conn,
      course: course,
      module: module,
      lecture: lecture
    } do
      {:ok, _view, html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "lecture", lecture: lecture.id, mode: "study_guide"}}"
        )

      assert html =~ "How GS1 works"
      assert html =~ "Write my study guide"
    end
  end

  describe "cross-course switching" do
    test "a learner with two enrollments can switch scope without leaving the hub", %{
      conn: conn,
      user: user
    } do
      # Two modules each, so selecting a course lands on the module picker
      # (which shows the course title) rather than auto-skipping past it.
      course1 = course_fixture(status: :published, title: "Course A")
      m1a = course_module_fixture(course_id: course1.id, position: 1)
      lecture_fixture(module_id: m1a.id, position: 1)
      m1b = course_module_fixture(course_id: course1.id, position: 2)
      lecture_fixture(module_id: m1b.id, position: 1)
      course2 = course_fixture(status: :published, title: "Course B")
      m2a = course_module_fixture(course_id: course2.id, position: 1)
      lecture_fixture(module_id: m2a.id, position: 1)
      m2b = course_module_fixture(course_id: course2.id, position: 2)
      lecture_fixture(module_id: m2b.id, position: 1)
      enroll!(user, course1)
      enroll!(user, course2)

      {:ok, view, _html} = live(conn, ~p"/learn/study")
      pid_before = view.pid

      view |> element("button[phx-value-slug='#{course1.slug}']") |> render_click()
      assert render(view) =~ course1.title

      view |> element("button", "Choose a different course") |> render_click()
      html = view |> element("button[phx-value-slug='#{course2.slug}']") |> render_click()

      assert html =~ course2.title
      assert view.pid == pid_before
    end
  end

  describe "live updates" do
    test "a status change for the currently-open scope updates the panel", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "flashcards"}}"
        )

      {:ok, set} = Assessments.get_or_create_flashcard_set(module)
      {:ok, 1} = Assessments.mark_flashcard_set_ready(set, [draft_flashcard_attrs()])

      assert render(view) =~ "Card 1 of 1"
    end

    test "a status change for a different scope is ignored", %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module1 = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module1.id, position: 1)
      module2 = course_module_fixture(course_id: course.id, position: 2)
      lecture_fixture(module_id: module2.id, position: 1)
      enroll!(user, course)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module1.id, scope: "module", mode: "flashcards"}}"
        )

      {:ok, other_set} = Assessments.get_or_create_flashcard_set(module2)
      {:ok, 1} = Assessments.mark_flashcard_set_ready(other_set, [draft_flashcard_attrs()])

      refute render(view) =~ "Card 1 of 1"
    end
  end
end
