defmodule WasomiWeb.AdminLive.QuizShow do
  use WasomiWeb, :live_view

  alias Wasomi.Assessments
  alias Wasomi.Catalog

  @impl true
  def mount(%{"course_slug" => course_slug, "quiz_id" => quiz_id}, _session, socket) do
    quiz = Assessments.get_quiz_with_questions!(quiz_id)
    course = Catalog.get_course_by_slug!(course_slug)

    if quiz.module.course_id != course.id do
      raise Ecto.NoResultsError, queryable: Assessments.Quiz
    end

    {:ok, push_navigate(socket, to: ~p"/admin/courses/#{course_slug}/quizzes/#{quiz_id}/edit")}
  end

  @impl true
  def render(assigns), do: ~H""
end
