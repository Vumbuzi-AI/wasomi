defmodule WasomiWeb.StudyHubLiveTest do
  use WasomiWeb.ConnCase
  use Oban.Testing, repo: Wasomi.Repo

  import Phoenix.LiveViewTest
  import Wasomi.CatalogFixtures
  import Wasomi.AssessmentsFixtures

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Workers.GenerateFlashcardsWorker
  alias Wasomi.Assessments.Workers.GeneratePracticeSetQuestionsWorker
  alias Wasomi.Enrollments

  setup :register_and_log_in_user

  defp enroll!(user, course) do
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, active} = Enrollments.activate_enrollment(pending)
    active
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
      refute html =~ "Timed quiz"
    end
  end

  describe "mode picker" do
    test "offers Flashcards, Extra practice, and Timed quiz for a whole-module scope", %{
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

      assert has_element?(view, "button[phx-value-mode='flashcards']", "Flashcards")
      assert has_element?(view, "button[phx-value-mode='practice']", "Extra practice")
      assert has_element?(view, "button[phx-value-mode='timed_quiz']", "Timed quiz")
    end

    test "hides Timed quiz for a single-lecture scope", %{conn: conn, user: user} do
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
      refute has_element?(view, "button[phx-value-mode='timed_quiz']")
    end

    test "requesting timed_quiz mode via URL for a lecture scope is rejected back to the mode step",
         %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "lecture", lecture: lecture.id, mode: "timed_quiz"}}"
        )

      assert has_element?(view, "h2", "What do you want to do?")
    end
  end

  describe "Flashcards content" do
    test "first visit creates a pending set and enqueues generation", %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "flashcards"}}"
        )

      assert html =~ "Generating your flashcards"
      {:ok, set} = Assessments.get_or_create_flashcard_set(module)
      assert set.status == :pending
      assert_enqueued(worker: GenerateFlashcardsWorker, args: %{"flashcard_set_id" => set.id})
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

  describe "Timed quiz content" do
    test "starts and can be submitted before finishing the module's lectures", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      quiz = quiz_fixture(%{module: module})
      question = question_fixture(%{quiz: quiz})
      correct = Enum.find(question.question_options, & &1.correct)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "timed_quiz"}}"
        )

      # No lecture has been completed, unlike CoursePlayerLive's Module Quiz —
      # the hub deliberately drops that gate for Timed quiz.
      html =
        view
        |> element("button[phx-value-seconds-per-question='60']")
        |> render_click()

      assert html =~ "Question 1 of 1"
      assert has_element?(view, "#quiz-countdown[data-total-seconds='60']")

      view
      |> element(
        "input[phx-value-question-id='#{question.id}'][phx-value-option-id='#{correct.id}']"
      )
      |> render_click()

      html = view |> element("form[phx-submit='submit-timed-quiz']") |> render_submit()

      assert html =~ "Quiz Passed!"
      assert [%{score_percent: 100}] = Assessments.list_submissions_for_user(user, quiz)
    end

    test "the deadline expiring auto-submits whatever was answered", %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      quiz = quiz_fixture(%{module: module})
      question_fixture(%{quiz: quiz})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "timed_quiz"}}"
        )

      view |> element("button[phx-value-seconds-per-question='30']") |> render_click()

      send(view.pid, :timed_quiz_expired)
      html = render(view)

      assert html =~ "Time&#39;s up!"
      assert [%{score_percent: 0}] = Assessments.list_submissions_for_user(user, quiz)
    end

    test "shows an empty state when the module has no quiz yet", %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      enroll!(user, course)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: "timed_quiz"}}"
        )

      assert render(view) =~ "doesn&#39;t have a quiz yet"
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
