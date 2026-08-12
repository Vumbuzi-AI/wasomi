defmodule WasomiWeb.AdminLive.QuizEditTest do
  use WasomiWeb.ConnCase
  use Oban.Testing, repo: Wasomi.Repo

  import Phoenix.LiveViewTest
  import Mox
  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Workers.GenerateQuizFromPDFWorker

  setup :verify_on_exit!

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  defp edit_path(quiz) do
    course_id = Assessments.get_quiz_with_questions!(quiz.id).module.course_id
    course_slug = Wasomi.Catalog.get_course!(course_id).slug
    ~p"/admin/courses/#{course_slug}/quizzes/#{quiz.id}/edit"
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  test "renders every question and saves prompt, explanation, choices, and correct answer", %{
    conn: conn
  } do
    quiz = quiz_fixture()
    question = question_fixture(%{quiz: quiz, status: :draft})

    {:ok, view, _html} = live(conn, edit_path(quiz))

    assert has_element?(view, "#question-#{question.id}")

    assert has_element?(
             view,
             "#question-form-#{question.id} input[aria-label='Mark option 1 correct']"
           )

    assert has_element?(
             view,
             "#question-form-#{question.id} input[aria-label='Mark option 4 correct']"
           )

    view
    |> form("#question-form-#{question.id}", %{
      "question-#{question.id}" => %{"correct_option_id" => "1"},
      question: %{
        prompt: "Which answer was updated?",
        explanation: "The second answer follows from the source material.",
        question_options: %{
          "0" => %{label: "Old answer"},
          "1" => %{label: "Updated answer"},
          "2" => %{label: "Distractor three"},
          "3" => %{label: "Distractor four"}
        }
      }
    })
    |> render_submit()

    [updated] = Assessments.get_quiz_with_questions!(quiz.id).questions
    assert updated.prompt == "Which answer was updated?"
    assert updated.explanation == "The second answer follows from the source material."

    assert Enum.map(updated.question_options, & &1.label) == [
             "Old answer",
             "Updated answer",
             "Distractor three",
             "Distractor four"
           ]

    assert Enum.map(updated.question_options, & &1.correct) == [false, true, false, false]
  end

  test "the save button for a question is disabled until it's actually edited", %{conn: conn} do
    quiz = quiz_fixture()
    question = question_fixture(%{quiz: quiz, status: :draft})

    {:ok, view, _html} = live(conn, edit_path(quiz))

    assert has_element?(
             view,
             "#question-form-#{question.id} button[type='submit'][disabled]",
             "Save question"
           )

    view
    |> form("#question-form-#{question.id}", %{
      question: %{prompt: "An edited prompt"}
    })
    |> render_change()

    refute has_element?(
             view,
             "#question-form-#{question.id} button[type='submit'][disabled]"
           )
  end

  test "admins can publish a single draft question without publishing the rest", %{conn: conn} do
    quiz = quiz_fixture()
    first = question_fixture(%{quiz: quiz, status: :draft, position: 1})
    second = question_fixture(%{quiz: quiz, status: :draft, position: 2})

    {:ok, view, _html} = live(conn, edit_path(quiz))

    view
    |> element("#question-#{first.id} button", "Publish")
    |> render_click()

    refute has_element?(view, "#question-#{first.id} button", "Publish")
    assert has_element?(view, "#question-#{second.id} button", "Publish")

    assert Assessments.get_question!(first.id).status == :published
    assert Assessments.get_question!(second.id).status == :draft
  end

  test "each question's correct-answer radios are scoped to its own form, not shared across the page",
       %{conn: conn} do
    quiz = quiz_fixture()
    first = question_fixture(%{quiz: quiz, position: 1})
    second = question_fixture(%{quiz: quiz, position: 2})

    {:ok, view, _html} = live(conn, edit_path(quiz))
    html = render(view)

    assert html =~ ~s(name="question-#{first.id}[correct_option_id]")
    assert html =~ ~s(name="question-#{second.id}[correct_option_id]")
    refute html =~ ~s(name="question[correct_option_id]")

    # Selecting a different correct option in question 2 leaves question 1's
    # selection untouched — this is the invariant the per-question radio-name
    # scoping protects (previously they shared one document-wide radio group).
    view
    |> form("#question-form-#{second.id}", %{
      "question-#{second.id}" => %{"correct_option_id" => "2"},
      question: %{question_options: %{"2" => %{}}}
    })
    |> render_change()

    assert has_element?(
             view,
             "#question-form-#{first.id} input[aria-label='Mark option 1 correct'][checked]"
           )
  end

  test "adds, removes, and reorders questions", %{conn: conn} do
    quiz = quiz_fixture()
    first = question_fixture(%{quiz: quiz, position: 1})
    second = question_fixture(%{quiz: quiz, position: 2})

    {:ok, view, _html} = live(conn, edit_path(quiz))

    view
    |> render_hook("reorder_questions", %{"ids" => [to_string(second.id), to_string(first.id)]})

    assert Enum.map(Assessments.get_quiz_with_questions!(quiz.id).questions, & &1.id) == [
             second.id,
             first.id
           ]

    view |> element("#add-question") |> render_click()

    view
    |> form("#new-question-form", %{
      "new-question" => %{"correct_option_id" => "0"},
      question: %{
        prompt: "A newly added question?",
        explanation: "This explains the new answer.",
        question_options: %{
          "0" => %{label: "Correct"},
          "1" => %{label: "Wrong one"},
          "2" => %{label: "Wrong two"},
          "3" => %{label: "Wrong three"}
        }
      }
    })
    |> render_submit()

    added =
      Assessments.get_quiz_with_questions!(quiz.id).questions
      |> Enum.find(&(&1.id not in [first.id, second.id]))

    assert has_element?(view, "#question-#{added.id}")

    view
    |> element("#question-#{first.id} button", "Remove")
    |> render_click()

    assert has_element?(view, "#delete-question-modal")

    view
    |> element("#delete-question-modal button", "Remove")
    |> render_click()

    refute has_element?(view, "#delete-question-modal")
    refute has_element?(view, "#question-#{first.id}")
    assert length(Assessments.get_quiz_with_questions!(quiz.id).questions) == 2
  end

  test "publishing a draft question or all drafts activates the quiz and marks questions published", %{conn: conn} do
    quiz = ready_quiz_fixture(%{active: false})
    first = question_fixture(%{quiz: quiz, status: :draft, position: 1})
    _second = question_fixture(%{quiz: quiz, status: :draft, position: 2})

    {:ok, view, _html} = live(conn, edit_path(quiz))

    view
    |> element("#question-#{first.id} button", "Publish")
    |> render_click()

    published = Assessments.get_quiz_with_questions!(quiz.id)
    assert published.active
    assert published.published_at

    view
    |> element("button", "Publish all drafts")
    |> render_click()

    view
    |> element("#publish-all-drafts-modal button", "Publish all")
    |> render_click()

    updated = Assessments.get_quiz_with_questions!(quiz.id)
    assert Enum.all?(updated.questions, &(&1.status == :published))
  end

  test "admin can rename the quiz inline", %{conn: conn} do
    quiz = quiz_fixture(%{title: "Original title"})
    {:ok, view, _html} = live(conn, edit_path(quiz))

    refute has_element?(view, "#quiz-title-form")

    view |> element("#edit-title") |> render_click()
    assert has_element?(view, "#quiz-title-form")

    view
    |> form("#quiz-title-form", quiz: %{title: "A brand new title"})
    |> render_submit()

    refute has_element?(view, "#quiz-title-form")
    assert has_element?(view, "#quiz-title", "A brand new title")
    assert Assessments.get_quiz!(quiz.id).title == "A brand new title"
  end

  test "renaming to a too-short title shows a validation error and doesn't save", %{conn: conn} do
    quiz = quiz_fixture(%{title: "Original title"})
    {:ok, view, _html} = live(conn, edit_path(quiz))

    view |> element("#edit-title") |> render_click()

    html =
      view
      |> form("#quiz-title-form", quiz: %{title: "ab"})
      |> render_submit()

    assert html =~ "should be at least 3 character"
    assert has_element?(view, "#quiz-title-form")
    assert Assessments.get_quiz!(quiz.id).title == "Original title"
  end

  test "admins can set the quiz's passing score", %{conn: conn} do
    quiz = quiz_fixture(%{passing_score_percent: 70})
    {:ok, view, html} = live(conn, edit_path(quiz))

    assert html =~ "Passing score"

    view
    |> form("#quiz-settings-form", quiz: %{passing_score_percent: "85"})
    |> render_submit()

    assert Assessments.get_quiz!(quiz.id).passing_score_percent == 85
  end

  test "an out-of-range passing score is rejected with a visible error", %{conn: conn} do
    quiz = quiz_fixture(%{passing_score_percent: 70})
    {:ok, view, _html} = live(conn, edit_path(quiz))

    html =
      view
      |> form("#quiz-settings-form", quiz: %{passing_score_percent: "150"})
      |> render_submit()

    assert html =~ "must be less than or equal to 100"
    assert Assessments.get_quiz!(quiz.id).passing_score_percent == 70
  end

  test "a prominent loading banner shows while a generation is pending or processing", %{
    conn: conn
  } do
    quiz = quiz_fixture()
    generation = quiz_generation_fixture(%{quiz: quiz, source_filename: "lecture-notes.pdf"})

    {:ok, view, html} = live(conn, edit_path(quiz))

    assert html =~ "Generating questions from lecture-notes.pdf"
    assert has_element?(view, "span[class*='animate-spin']")

    Assessments.mark_generation_processing(generation)
    assert render(view) =~ "Generating questions from lecture-notes.pdf"
  end

  test "the loading banner disappears once a generation finishes or fails", %{conn: conn} do
    quiz = quiz_fixture()
    generation = quiz_generation_fixture(%{quiz: quiz})

    {:ok, view, html} = live(conn, edit_path(quiz))
    assert html =~ "Generating questions from"

    Assessments.mark_generation_failed(generation, "boom")
    refute render(view) =~ "Generating questions from"
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

    {:ok, view, _html} = live(conn, edit_path(quiz))

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

    {:ok, view, _html} = live(conn, edit_path(quiz))

    assert has_element?(view, "span.bg-mint", "2 generated · 2 to review")
    refute has_element?(view, "span.bg-neutral-50", "reviewed")

    view
    |> element("button", "Discard 2 draft(s)")
    |> render_click()

    view
    |> element("#discard-generation-modal button", "Discard drafts")
    |> render_click()

    assert has_element?(view, "span.bg-neutral-50", "2 generated · reviewed")
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

    {:ok, view, _html} = live(conn, edit_path(quiz))

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

    {:ok, view, _html} = live(conn, edit_path(quiz))

    refute has_element?(view, "#delete-all-drafts-modal")

    view
    |> element("button", "Delete all drafts")
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

    {:ok, view, _html} = live(conn, edit_path(quiz))

    refute has_element?(view, "#publish-all-drafts-modal")

    view
    |> element("button", "Publish all drafts")
    |> render_click()

    assert has_element?(view, "#publish-all-drafts-modal")

    view
    |> element("#publish-all-drafts-modal button", "Publish all")
    |> render_click()

    refute has_element?(view, "#publish-all-drafts-modal")
    refute has_element?(view, "button", "Publish all drafts")

    questions = Assessments.get_quiz_with_questions!(quiz.id).questions
    assert length(questions) == 4
    assert Enum.all?(questions, &(&1.status == :published))
    assert Enum.find(questions, &(&1.id == already_published.id))
  end

  test "cancelling the publish-all confirmation leaves drafts untouched", %{conn: conn} do
    quiz = quiz_fixture()
    question = question_fixture(%{quiz: quiz, status: :draft})

    {:ok, view, _html} = live(conn, edit_path(quiz))

    view |> element("button", "Publish all drafts") |> render_click()
    view |> element("#publish-all-drafts-modal button", "Cancel") |> render_click()

    refute has_element?(view, "#publish-all-drafts-modal")
    assert Assessments.get_question!(question.id).status == :draft
  end

  test "admins can manually add a multiple-choice question", %{conn: conn} do
    quiz = quiz_fixture()
    {:ok, view, _html} = live(conn, edit_path(quiz))

    view |> element("#add-question") |> render_click()
    assert has_element?(view, "#new-question-form")

    view
    |> form("#new-question-form", %{
      "new-question" => %{"correct_option_id" => "0"},
      question: %{
        prompt: "A manually added question?",
        question_options: %{
          "0" => %{label: "Correct"},
          "1" => %{label: "Wrong one"},
          "2" => %{label: "Wrong two"},
          "3" => %{label: "Wrong three"}
        }
      }
    })
    |> render_submit()

    refute has_element?(view, "#new-question-form")

    [question] = Assessments.get_quiz_with_questions!(quiz.id).questions
    assert question.prompt == "A manually added question?"
    assert length(question.question_options) == 4
  end

  test "admins can manually add a true/false question", %{conn: conn} do
    quiz = quiz_fixture()
    {:ok, view, _html} = live(conn, edit_path(quiz))

    view |> element("#add-true-false-question") |> render_click()
    assert has_element?(view, "#new-question-form")

    view
    |> form("#new-question-form", %{
      "new-question" => %{"correct_option_id" => "0"},
      question: %{prompt: "True or false question?"}
    })
    |> render_submit()

    refute has_element?(view, "#new-question-form")

    [question] = Assessments.get_quiz_with_questions!(quiz.id).questions
    assert question.prompt == "True or false question?"
    assert Enum.map(question.question_options, & &1.label) == ["True", "False"]
    assert Enum.map(question.question_options, & &1.correct) == [true, false]
  end

  test "not selecting a correct option shows a visible nudge instead of silently failing", %{
    conn: conn
  } do
    quiz = quiz_fixture()
    {:ok, view, _html} = live(conn, edit_path(quiz))

    view |> element("#add-question") |> render_click()

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
    {:ok, view, _html} = live(conn, edit_path(quiz))

    view |> element("#add-question") |> render_click()
    view |> element("#new-question-form button", "Cancel") |> render_click()

    refute has_element?(view, "#new-question-form")
    assert Assessments.get_quiz_with_questions!(quiz.id).questions == []
  end

  defp ready_quiz_fixture(opts \\ []) do
    quiz = quiz_fixture(opts)
    lecture = lecture_fixture(module_id: quiz.module_id)
    lecture_quiz_fixture(lecture: lecture)
    quiz
  end

  test "disables module quiz generation controls and displays tooltip warning when lectures lack a lecture quiz", %{
    conn: conn
  } do
    quiz = quiz_fixture()
    {:ok, view, _html} = live(conn, edit_path(quiz))

    assert render(view) =~ "Module Quiz Generation Locked"
    assert render(view) =~ "Every lecture in this module must have a generated lecture quiz before generating the module quiz."
    assert has_element?(view, "#generate-questions-form button[disabled]")
  end

  test "uploading a PDF enqueues generation without an admin-chosen question count", %{
    conn: conn
  } do
    quiz = ready_quiz_fixture()
    {:ok, view, _html} = live(conn, edit_path(quiz))

    expect(Wasomi.AssessmentsStorageMock, :upload, fn _key, _binary -> :ok end)

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
    quiz = ready_quiz_fixture()
    {:ok, view, _html} = live(conn, edit_path(quiz))

    pdf =
      file_input(view, "#generate-questions-form", :source_pdf, [
        %{name: "huge.pdf", content: String.duplicate("a", 26_000_000), type: "application/pdf"}
      ])

    assert {:error, [[_ref, :too_large]]} = render_upload(pdf, "huge.pdf")
    assert render(view) =~ "File is too large (max 25MB)."
    refute_enqueued(worker: GenerateQuizFromPDFWorker)
  end

  test "a generation-record creation failure shows an error instead of crashing", %{conn: conn} do
    quiz = ready_quiz_fixture()
    {:ok, view, _html} = live(conn, edit_path(quiz))

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

  test "a storage upload failure shows an error instead of crashing", %{conn: conn} do
    quiz = ready_quiz_fixture()
    {:ok, view, _html} = live(conn, edit_path(quiz))

    expect(Wasomi.AssessmentsStorageMock, :upload, fn _key, _binary ->
      {:error, :r2_not_configured}
    end)

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

  test "course mismatch raises instead of exposing another course's quiz", %{conn: conn} do
    quiz = quiz_fixture()
    other_course = course_fixture()

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/admin/courses/#{other_course.slug}/quizzes/#{quiz.id}/edit")
    end
  end

  test "admins can dynamically add and remove options in the quiz editor page", %{conn: conn} do
    quiz = quiz_fixture()
    question = question_fixture(%{quiz: quiz, status: :draft})

    {:ok, view, _html} = live(conn, edit_path(quiz))

    # Starts with 4 options, so we cannot add more.
    refute has_element?(view, "#question-form-#{question.id} button", "Add option")

    # Click remove option on the last element (index 3)
    view
    |> element("#question-form-#{question.id} button[title='Remove option'][phx-value-index='3']")
    |> render_click()

    # Now has 3 options. "Add option" should be visible.
    assert has_element?(view, "#question-form-#{question.id} button", "Add option")

    # Click add option
    view
    |> element("#question-form-#{question.id} button", "Add option")
    |> render_click()

    # Back to 4 options, "Add option" is hidden again.
    refute has_element?(view, "#question-form-#{question.id} button", "Add option")
  end
end
