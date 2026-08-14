defmodule WasomiWeb.AdminLive.PracticeQuestionsEditTest do
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

  defp edit_path(module) do
    course = Wasomi.Catalog.get_course!(module.course_id)
    ~p"/admin/courses/#{course.slug}/modules/#{module.id}/practice"
  end

  describe "authorization" do
    test "unauthenticated users are redirected" do
      module = course_module_fixture()
      conn = build_conn()
      assert {:error, redirect} = live(conn, edit_path(module))
      assert {:redirect, %{to: "/users/log_in"}} = redirect
    end

    test "non-admin student users are redirected", %{conn: conn} do
      module = course_module_fixture()
      student = user_fixture()
      conn = conn |> log_in_user(student)
      assert {:error, redirect} = live(conn, edit_path(module))
      assert {:redirect, %{to: "/"}} = redirect
    end
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  test "mount renders the page with module title", %{conn: conn} do
    module = course_module_fixture(%{title: "Test Module 1"})
    {:ok, _view, html} = live(conn, edit_path(module))
    assert html =~ "Practice questions"
    assert html =~ "Test Module 1"
  end

  test "mount shows empty state when no questions exist", %{conn: conn} do
    module = course_module_fixture()
    {:ok, _view, html} = live(conn, edit_path(module))
    assert html =~ "No practice questions yet."
  end

  test "creating a new practice question works", %{conn: conn} do
    module = course_module_fixture()
    {:ok, view, _html} = live(conn, edit_path(module))

    view |> element("button", "Add question") |> render_click()

    assert has_element?(view, "h2", "New practice question")

    view
    |> form("form[phx-submit='save_new_practice_question']", %{
      "new-practice-question" => %{"correct_option_id" => "1"},
      "practice_question" => %{
        "prompt" => "What is Elixir?",
        "practice_question_options" => %{
          "0" => %{"label" => "A programming language"},
          "1" => %{"label" => "A snake"},
          "2" => %{"label" => "A type of coffee"},
          "3" => %{"label" => "A car"}
        }
      }
    })
    |> render_submit()

    questions = Assessments.list_all_practice_questions(module)
    assert length(questions) == 1
    [q] = questions
    assert q.prompt == "What is Elixir?"

    assert has_element?(view, "p", "What is Elixir?")
  end

  test "deleting a practice question works", %{conn: conn} do
    module = course_module_fixture()
    question = practice_question_fixture(%{module: module})

    {:ok, view, _html} = live(conn, edit_path(module))

    assert has_element?(view, "p", question.prompt)

    view |> element("button", "Remove") |> render_click()

    assert has_element?(view, "#delete-practice-question-modal")

    view |> element("#delete-practice-question-modal button", "Remove") |> render_click()

    refute has_element?(view, "p", question.prompt)
    assert Assessments.list_all_practice_questions(module) == []
  end

  test "generating AI practice questions works", %{conn: conn} do
    module = course_module_fixture()

    Mox.expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn _text, _opts ->
      {:ok,
       [
         %{
           prompt: "Generated AI Question?",
           options: [
             %{label: "Yes", correct: true},
             %{label: "No", correct: false}
           ]
         }
       ]}
    end)

    {:ok, view, _html} = live(conn, edit_path(module))

    view |> element("button", "Generate with AI") |> render_click()

    _html = render_async(view)

    assert has_element?(view, "p", "Generated AI Question?")
    assert length(Assessments.list_all_practice_questions(module)) == 1
  end
end
