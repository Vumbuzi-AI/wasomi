defmodule WasomiWeb.AdminLive.QuizEditTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures

  alias Wasomi.Assessments

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  defp edit_path(quiz) do
    course_id = Assessments.get_quiz_with_questions!(quiz.id).module.course_id
    ~p"/admin/courses/#{course_id}/quizzes/#{quiz.id}/edit"
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
    |> form("#question-form-#{question.id}",
      question: %{
        prompt: "Which answer was updated?",
        explanation: "The second answer follows from the source material.",
        correct_option_id: "1",
        question_options: %{
          "0" => %{label: "Old answer"},
          "1" => %{label: "Updated answer"},
          "2" => %{label: "Distractor three"},
          "3" => %{label: "Distractor four"}
        }
      }
    )
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
    |> form("#new-question-form",
      question: %{
        prompt: "A newly added question?",
        explanation: "This explains the new answer.",
        correct_option_id: "0",
        question_options: %{
          "0" => %{label: "Correct"},
          "1" => %{label: "Wrong one"},
          "2" => %{label: "Wrong two"},
          "3" => %{label: "Wrong three"}
        }
      }
    )
    |> render_submit()

    added =
      Assessments.get_quiz_with_questions!(quiz.id).questions
      |> Enum.find(&(&1.id not in [first.id, second.id]))

    assert has_element?(view, "#question-#{added.id}")

    view
    |> element("#question-#{first.id} button", "Remove")
    |> render_click()

    refute has_element?(view, "#question-#{first.id}")
    assert length(Assessments.get_quiz_with_questions!(quiz.id).questions) == 2
  end

  test "publish reports completeness errors and leaves an empty quiz inactive", %{conn: conn} do
    quiz = quiz_fixture()
    {:ok, view, _html} = live(conn, edit_path(quiz))

    html = view |> element("#publish-quiz") |> render_click()

    assert html =~ "Add at least one question before publishing."
    refute Assessments.get_quiz!(quiz.id).active
  end

  test "publishing marks the quiz active and publishes all questions", %{conn: conn} do
    quiz = quiz_fixture()
    first = question_fixture(%{quiz: quiz, status: :draft, position: 1})
    second = question_fixture(%{quiz: quiz, status: :draft, position: 2})

    {:ok, view, _html} = live(conn, edit_path(quiz))
    view |> element("#publish-quiz") |> render_click()

    assert has_element?(view, "#quiz-status", "Active")
    published = Assessments.get_quiz_with_questions!(quiz.id)
    assert published.active
    assert published.published_at
    assert Enum.map(published.questions, & &1.id) == [first.id, second.id]
    assert Enum.all?(published.questions, &(&1.status == :published))
  end

  test "course mismatch raises instead of exposing another course's quiz", %{conn: conn} do
    quiz = quiz_fixture()
    other_course = course_fixture()

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/admin/courses/#{other_course.id}/quizzes/#{quiz.id}/edit")
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
