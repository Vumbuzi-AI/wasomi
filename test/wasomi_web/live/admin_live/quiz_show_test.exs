defmodule WasomiWeb.AdminLive.QuizShowTest do
  use WasomiWeb.ConnCase
  use Oban.Testing, repo: Wasomi.Repo

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Workers.GenerateQuizFromPDFWorker

  defp admin_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  defp quiz_path(quiz) do
    course_id = Assessments.get_quiz_with_questions!(quiz.id).module.course_id
    ~p"/admin/courses/#{course_id}/quizzes/#{quiz.id}"
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  test "admins can set the quiz's passing score", %{conn: conn} do
    quiz = quiz_fixture(%{passing_score_percent: 70})
    {:ok, view, html} = live(conn, quiz_path(quiz))

    assert html =~ "Passing score"

    view
    |> form("#quiz-settings-form", quiz: %{passing_score_percent: "85"})
    |> render_submit()

    assert Assessments.get_quiz!(quiz.id).passing_score_percent == 85
  end

  test "a course_id that doesn't match the quiz's real course 404s", %{conn: conn} do
    quiz = quiz_fixture()
    other_course = course_fixture()

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/admin/courses/#{other_course.id}/quizzes/#{quiz.id}")
    end
  end

  test "an out-of-range passing score is rejected with a visible error", %{conn: conn} do
    quiz = quiz_fixture(%{passing_score_percent: 70})
    {:ok, view, _html} = live(conn, quiz_path(quiz))

    html =
      view
      |> form("#quiz-settings-form", quiz: %{passing_score_percent: "150"})
      |> render_submit()

    assert html =~ "must be less than or equal to 100"
    assert Assessments.get_quiz!(quiz.id).passing_score_percent == 70
  end

  test "admins can edit a draft question's prompt, options, and correct answer", %{conn: conn} do
    question = question_fixture(%{status: :draft})
    quiz = Assessments.get_quiz!(question.quiz_id)

    {:ok, view, _html} = live(conn, quiz_path(quiz))

    assert has_element?(view, "#question-form-#{question.id}") == false

    view
    |> element("button", "Edit")
    |> render_click()

    assert has_element?(view, "#question-form-#{question.id}")

    view
    |> form("#question-form-#{question.id}",
      question: %{
        prompt: "What is the updated question?",
        correct_option_id: "1",
        question_options: %{
          "0" => %{label: "Wrong A"},
          "1" => %{label: "Right B"},
          "2" => %{label: "Wrong C"},
          "3" => %{label: "Wrong D"}
        }
      }
    )
    |> render_submit()

    updated =
      Assessments.get_quiz_with_questions!(quiz.id).questions
      |> Enum.find(&(&1.id == question.id))

    assert updated.prompt == "What is the updated question?"

    options = Enum.sort_by(updated.question_options, & &1.position)
    assert Enum.map(options, & &1.label) == ["Wrong A", "Right B", "Wrong C", "Wrong D"]
    assert Enum.map(options, & &1.correct) == [false, true, false, false]

    refute has_element?(view, "#question-form-#{question.id}")
    assert has_element?(view, "li", "What is the updated question?")
  end

  test "cancelling an edit discards unsaved changes", %{conn: conn} do
    question = question_fixture(%{status: :draft})
    quiz = Assessments.get_quiz!(question.quiz_id)

    {:ok, view, _html} = live(conn, quiz_path(quiz))

    view |> element("button", "Edit") |> render_click()
    assert has_element?(view, "#question-form-#{question.id}")

    view |> element("button", "Cancel") |> render_click()

    refute has_element?(view, "#question-form-#{question.id}")
    assert Assessments.get_question!(question.id).prompt == question.prompt
  end

  test "saving with an invalid option set re-renders the form with errors", %{conn: conn} do
    question = question_fixture(%{status: :draft})
    quiz = Assessments.get_quiz!(question.quiz_id)

    {:ok, view, _html} = live(conn, quiz_path(quiz))

    view |> element("button", "Edit") |> render_click()

    html =
      view
      |> form("#question-form-#{question.id}",
        question: %{
          prompt: "",
          correct_option_id: "0",
          question_options: %{
            "0" => %{label: "A"},
            "1" => %{label: "B"},
            "2" => %{label: "C"},
            "3" => %{label: "D"}
          }
        }
      )
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    assert has_element?(view, "#question-form-#{question.id}")
  end

  test "deleting a draft question requires confirmation via the modal", %{conn: conn} do
    question = question_fixture(%{status: :draft})
    quiz = Assessments.get_quiz!(question.quiz_id)

    {:ok, view, _html} = live(conn, quiz_path(quiz))

    refute has_element?(view, "#delete-question-modal")

    view
    |> element("li button[title='Delete question']")
    |> render_click()

    assert has_element?(view, "#delete-question-modal")
    assert render(view) =~ "Delete this draft question?"

    view
    |> element("#delete-question-modal button", "Cancel")
    |> render_click()

    assert Assessments.get_question!(question.id)

    view
    |> element("li button[title='Delete question']")
    |> render_click()

    view
    |> element("#delete-question-modal button", "Delete")
    |> render_click()

    assert_raise Ecto.NoResultsError, fn -> Assessments.get_question!(question.id) end
    refute has_element?(view, "li", question.prompt)
  end

  test "admins can manually add a question when AI generation missed some", %{conn: conn} do
    quiz = quiz_fixture()

    {:ok, view, _html} = live(conn, quiz_path(quiz))

    refute has_element?(view, "#new-question-form")

    view |> element("button", "Add question") |> render_click()

    view
    |> element("button", "Multiple choice")
    |> render_click()

    assert has_element?(view, "#new-question-form")

    view
    |> form("#new-question-form",
      question: %{
        prompt: "What did the AI miss?",
        correct_option_id: "2",
        question_options: %{
          "0" => %{label: "Wrong A"},
          "1" => %{label: "Wrong B"},
          "2" => %{label: "Right C"},
          "3" => %{label: "Wrong D"}
        }
      }
    )
    |> render_submit()

    refute has_element?(view, "#new-question-form")
    assert has_element?(view, "li", "What did the AI miss?")

    [question] =
      Assessments.get_quiz_with_questions!(quiz.id).questions
      |> Enum.filter(&(&1.prompt == "What did the AI miss?"))

    assert question.status == :draft

    options = Enum.sort_by(question.question_options, & &1.position)
    assert Enum.map(options, & &1.label) == ["Wrong A", "Wrong B", "Right C", "Wrong D"]
    assert Enum.map(options, & &1.correct) == [false, false, true, false]
  end

  test "admins can manually add a true/false question", %{conn: conn} do
    quiz = quiz_fixture()
    {:ok, view, _html} = live(conn, quiz_path(quiz))

    view |> element("button", "Add question") |> render_click()

    view
    |> element("button", "True/False")
    |> render_click()

    assert has_element?(view, "#new-question-form")

    view
    |> form("#new-question-form",
      question: %{
        prompt: "The document was written for adult learners.",
        correct_option_id: "0",
        question_options: %{
          "0" => %{label: "True"},
          "1" => %{label: "False"}
        }
      }
    )
    |> render_submit()

    [question] =
      Assessments.get_quiz_with_questions!(quiz.id).questions
      |> Enum.filter(&(&1.prompt == "The document was written for adult learners."))

    options = Enum.sort_by(question.question_options, & &1.position)
    assert Enum.map(options, & &1.label) == ["True", "False"]
    assert Enum.map(options, & &1.correct) == [true, false]
  end

  test "not selecting a correct option shows a visible nudge instead of silently failing", %{
    conn: conn
  } do
    quiz = quiz_fixture()
    {:ok, view, _html} = live(conn, quiz_path(quiz))

    view |> element("button", "Add question") |> render_click()
    view |> element("button", "Multiple choice") |> render_click()

    html =
      view
      |> form("#new-question-form",
        question: %{
          prompt: "A question with no marked answer",
          question_options: %{
            "0" => %{label: "A"},
            "1" => %{label: "B"},
            "2" => %{label: "C"},
            "3" => %{label: "D"}
          }
        }
      )
      |> render_submit()

    assert html =~ "must include at least one correct option"
    assert has_element?(view, "#new-question-form")

    assert Assessments.get_quiz_with_questions!(quiz.id).questions == []
  end

  test "cancelling adding a question doesn't create anything", %{conn: conn} do
    quiz = quiz_fixture()
    {:ok, view, _html} = live(conn, quiz_path(quiz))

    view |> element("button", "Add question") |> render_click()
    view |> element("button", "Multiple choice") |> render_click()
    view |> element("#new-question-form button", "Cancel") |> render_click()

    refute has_element?(view, "#new-question-form")
    assert Assessments.get_quiz_with_questions!(quiz.id).questions == []
  end

  test "cancelling at the question-type picker returns to the closed state", %{conn: conn} do
    quiz = quiz_fixture()
    {:ok, view, _html} = live(conn, quiz_path(quiz))

    view |> element("button", "Add question") |> render_click()
    assert has_element?(view, "button", "Multiple choice")
    refute has_element?(view, "#new-question-form")

    view |> element("button", "Cancel") |> render_click()

    refute has_element?(view, "button", "Multiple choice")
    assert has_element?(view, "button", "Add question")
  end

  test "admins can discard all remaining draft questions from one generation batch", %{
    conn: conn
  } do
    quiz = quiz_fixture()
    admin = admin_fixture()

    {:ok, generation} = Assessments.create_generation(quiz, admin, "batch.pdf")

    drafts = [
      draft_question_attrs(%{prompt: "Batch question 1"}),
      draft_question_attrs(%{prompt: "Batch question 2"})
    ]

    {:ok, 2} = Assessments.create_draft_questions_and_mark_ready(generation, drafts)

    {:ok, view, _html} = live(conn, quiz_path(quiz))

    assert has_element?(view, "button", "Discard 2 draft(s)")
    refute has_element?(view, "#discard-generation-modal")

    view
    |> element("button", "Discard 2 draft(s)")
    |> render_click()

    assert has_element?(view, "#discard-generation-modal")

    view
    |> element("#discard-generation-modal button", "Discard drafts")
    |> render_click()

    refute has_element?(view, "#discard-generation-modal")
    assert Assessments.get_quiz_with_questions!(quiz.id).questions == []
  end

  test "a ready generation's badge reflects remaining drafts, then calms down once reviewed", %{
    conn: conn
  } do
    quiz = quiz_fixture()
    admin = admin_fixture()

    {:ok, generation} = Assessments.create_generation(quiz, admin, "batch.pdf")

    {:ok, 2} =
      Assessments.create_draft_questions_and_mark_ready(generation, [
        draft_question_attrs(%{prompt: "Batch question 1"}),
        draft_question_attrs(%{prompt: "Batch question 2"})
      ])

    {:ok, view, _html} = live(conn, quiz_path(quiz))

    assert has_element?(view, "span.bg-mint", "2 generated · 2 to review")
    refute has_element?(view, "span.bg-soft", "reviewed")

    view
    |> element("button", "Discard 2 draft(s)")
    |> render_click()

    view
    |> element("#discard-generation-modal button", "Discard drafts")
    |> render_click()

    assert has_element?(view, "span.bg-soft", "2 generated · reviewed")
    refute has_element?(view, "span.bg-mint", "to review")
  end

  test "discarding a batch leaves drafts from other batches and published questions alone", %{
    conn: conn
  } do
    quiz = quiz_fixture()
    admin = admin_fixture()

    {:ok, bad_generation} = Assessments.create_generation(quiz, admin, "bad.pdf")

    {:ok, 1} =
      Assessments.create_draft_questions_and_mark_ready(bad_generation, [
        draft_question_attrs(%{prompt: "Bad batch question"})
      ])

    published = question_fixture(%{quiz: quiz, prompt: "Already published", position: 5})
    {:ok, published} = Assessments.publish_question(published)

    {:ok, view, _html} = live(conn, quiz_path(quiz))

    view
    |> element("button", "Discard 1 draft(s)")
    |> render_click()

    view
    |> element("#discard-generation-modal button", "Discard drafts")
    |> render_click()

    remaining = Assessments.get_quiz_with_questions!(quiz.id).questions
    assert Enum.map(remaining, & &1.id) == [published.id]
  end

  test "admins can delete all drafts on the quiz regardless of which batch created them", %{
    conn: conn
  } do
    quiz = quiz_fixture()
    admin = admin_fixture()

    {:ok, generation_1} = Assessments.create_generation(quiz, admin, "one.pdf")
    {:ok, generation_2} = Assessments.create_generation(quiz, admin, "two.pdf")

    {:ok, 1} =
      Assessments.create_draft_questions_and_mark_ready(generation_1, [
        draft_question_attrs(%{prompt: "From batch one"})
      ])

    {:ok, 1} =
      Assessments.create_draft_questions_and_mark_ready(generation_2, [
        draft_question_attrs(%{prompt: "From batch two"})
      ])

    published = question_fixture(%{quiz: quiz, prompt: "Already published", position: 5})
    {:ok, published} = Assessments.publish_question(published)

    {:ok, view, _html} = live(conn, quiz_path(quiz))

    assert has_element?(view, "span", "2")
    refute has_element?(view, "#delete-all-drafts-modal")

    view
    |> element("button", "Delete all")
    |> render_click()

    assert has_element?(view, "#delete-all-drafts-modal")

    view
    |> element("#delete-all-drafts-modal button", "Delete all")
    |> render_click()

    refute has_element?(view, "#delete-all-drafts-modal")

    remaining = Assessments.get_quiz_with_questions!(quiz.id).questions
    assert Enum.map(remaining, & &1.id) == [published.id]
  end

  test "admins can publish all remaining drafts at once after reviewing them", %{conn: conn} do
    quiz = quiz_fixture()
    admin = admin_fixture()

    {:ok, generation} = Assessments.create_generation(quiz, admin, "batch.pdf")

    {:ok, 3} =
      Assessments.create_draft_questions_and_mark_ready(generation, [
        draft_question_attrs(%{prompt: "Draft one"}),
        draft_question_attrs(%{prompt: "Draft two"}),
        draft_question_attrs(%{prompt: "Draft three"})
      ])

    already_published =
      question_fixture(%{quiz: quiz, prompt: "Already published", position: 10})

    {:ok, already_published} = Assessments.publish_question(already_published)

    {:ok, view, _html} = live(conn, quiz_path(quiz))

    refute has_element?(view, "#publish-all-drafts-modal")

    view
    |> element("button", "Publish all")
    |> render_click()

    assert has_element?(view, "#publish-all-drafts-modal")

    view
    |> element("#publish-all-drafts-modal button", "Publish all")
    |> render_click()

    refute has_element?(view, "#publish-all-drafts-modal")
    refute has_element?(view, "button", "Publish all")

    questions = Assessments.get_quiz_with_questions!(quiz.id).questions
    assert length(questions) == 4
    assert Enum.all?(questions, &(&1.status == :published))
    assert Enum.find(questions, &(&1.id == already_published.id))
  end

  test "cancelling the publish-all confirmation leaves drafts untouched", %{conn: conn} do
    quiz = quiz_fixture()
    question = question_fixture(%{quiz: quiz, status: :draft})

    {:ok, view, _html} = live(conn, quiz_path(quiz))

    view |> element("button", "Publish all") |> render_click()
    view |> element("#publish-all-drafts-modal button", "Cancel") |> render_click()

    refute has_element?(view, "#publish-all-drafts-modal")
    assert Assessments.get_question!(question.id).status == :draft
  end

  test "uploading a PDF enqueues generation without an admin-chosen question count", %{
    conn: conn
  } do
    quiz = quiz_fixture()
    {:ok, view, _html} = live(conn, quiz_path(quiz))

    refute has_element?(view, "input[name='question_count']")

    pdf =
      file_input(view, "#generate-questions-form", :source_pdf, [
        %{name: "manual.pdf", content: "%PDF-1.4 fake", type: "application/pdf"}
      ])

    assert render_upload(pdf, "manual.pdf") =~ ~s(value="100")

    view
    |> form("#generate-questions-form", %{})
    |> render_submit()

    assert_enqueued(worker: GenerateQuizFromPDFWorker)

    [job] = all_enqueued(worker: GenerateQuizFromPDFWorker)
    refute Map.has_key?(job.args, "question_count")
  end

  test "a PDF over the 25MB limit is rejected with a clear message", %{conn: conn} do
    quiz = quiz_fixture()
    {:ok, view, _html} = live(conn, quiz_path(quiz))

    pdf =
      file_input(view, "#generate-questions-form", :source_pdf, [
        %{name: "huge.pdf", content: String.duplicate("a", 26_000_000), type: "application/pdf"}
      ])

    assert {:error, [[_ref, :too_large]]} = render_upload(pdf, "huge.pdf")
    assert render(view) =~ "File is too large (max 25MB)."
    refute_enqueued(worker: GenerateQuizFromPDFWorker)
  end

  test "a generation-record creation failure shows an error instead of crashing", %{conn: conn} do
    quiz = quiz_fixture()
    {:ok, view, _html} = live(conn, quiz_path(quiz))

    # Force Assessments.create_generation/3 to fail its assoc_constraint(:quiz)
    # check by deleting the quiz out from under the already-mounted socket.
    Assessments.delete_quiz(quiz)

    pdf =
      file_input(view, "#generate-questions-form", :source_pdf, [
        %{name: "manual.pdf", content: "%PDF-1.4 fake", type: "application/pdf"}
      ])

    assert render_upload(pdf, "manual.pdf") =~ ~s(value="100")

    html =
      view
      |> form("#generate-questions-form", %{})
      |> render_submit()

    assert html =~ "Could not start generation"
    refute_enqueued(worker: GenerateQuizFromPDFWorker)
    assert Process.alive?(view.pid)
  end
end
