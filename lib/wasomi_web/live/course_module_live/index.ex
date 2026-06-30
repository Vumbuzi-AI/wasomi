defmodule WasomiWeb.CourseModuleLive.Index do
  use WasomiWeb, :live_view

  alias Wasomi.Catalog
  alias Wasomi.Catalog.CourseModule

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :modules, Catalog.list_modules())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Course module")
    |> assign(:course_module, Catalog.get_course_module!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Course module")
    |> assign(:course_module, %CourseModule{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Modules")
    |> assign(:course_module, nil)
  end

  @impl true
  def handle_info({WasomiWeb.CourseModuleLive.FormComponent, {:saved, course_module}}, socket) do
    {:noreply, stream_insert(socket, :modules, course_module)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    course_module = Catalog.get_course_module!(id)
    {:ok, _} = Catalog.delete_course_module(course_module)

    {:noreply, stream_delete(socket, :modules, course_module)}
  end
end
