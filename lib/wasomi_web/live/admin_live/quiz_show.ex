defmodule WasomiWeb.AdminLive.QuizShow do
  use WasomiWeb, :live_view

  alias Wasomi.Assessments

  @impl true
  def mount(%{"course_id" => course_id, "quiz_id" => quiz_id}, _session, socket) do
    quiz = Assessments.get_quiz_with_questions!(quiz_id)

    if to_string(quiz.module.course_id) != course_id do
      raise Ecto.NoResultsError, queryable: Assessments.Quiz
    end

    {:ok, push_navigate(socket, to: ~p"/admin/courses/#{course_id}/quizzes/#{quiz_id}/edit")}
  end

  @impl true
  def render(assigns), do: ~H""
end
