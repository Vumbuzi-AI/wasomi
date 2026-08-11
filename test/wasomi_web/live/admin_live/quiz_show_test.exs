defmodule WasomiWeb.AdminLive.QuizShowTest do
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

  defp quiz_path(quiz) do
    course_id = Assessments.get_quiz_with_questions!(quiz.id).module.course_id
    course_slug = Wasomi.Catalog.get_course!(course_id).slug
    ~p"/admin/courses/#{course_slug}/quizzes/#{quiz.id}"
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  test "redirects to the edit page", %{conn: conn} do
    quiz = quiz_fixture()
    course_id = Assessments.get_quiz_with_questions!(quiz.id).module.course_id
    course_slug = Wasomi.Catalog.get_course!(course_id).slug

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, quiz_path(quiz))
    assert to == ~p"/admin/courses/#{course_slug}/quizzes/#{quiz.id}/edit"
  end

  test "a course_slug mismatch still raises", %{conn: conn} do
    quiz = quiz_fixture()
    other_course = course_fixture()

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/admin/courses/#{other_course.slug}/quizzes/#{quiz.id}")
    end
  end
end
