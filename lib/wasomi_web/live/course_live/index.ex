defmodule WasomiWeb.CourseLive.Index do
  use WasomiWeb, :live_view

  alias Wasomi.Catalog
  alias Wasomi.Catalog.Course

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :courses, Catalog.list_courses())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Course")
    |> assign(:course, Catalog.get_course!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Course")
    |> assign(:course, %Course{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Courses")
    |> assign(:course, nil)
  end

  @impl true
  def handle_info({WasomiWeb.CourseLive.FormComponent, {:saved, course}}, socket) do
    {:noreply, stream_insert(socket, :courses, course)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    course = Catalog.get_course!(id)
    {:ok, _} = Catalog.delete_course(course)

    {:noreply, stream_delete(socket, :courses, course)}
  end
end
