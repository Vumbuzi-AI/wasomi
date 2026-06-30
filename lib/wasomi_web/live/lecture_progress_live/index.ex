defmodule WasomiWeb.LectureProgressLive.Index do
  use WasomiWeb, :live_view

  alias Wasomi.Learning
  alias Wasomi.Learning.LectureProgress

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :lecture_progress_collection, Learning.list_lecture_progress())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Lecture progress")
    |> assign(:lecture_progress, Learning.get_lecture_progress!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Lecture progress")
    |> assign(:lecture_progress, %LectureProgress{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Lecture progress")
    |> assign(:lecture_progress, nil)
  end

  @impl true
  def handle_info(
        {WasomiWeb.LectureProgressLive.FormComponent, {:saved, lecture_progress}},
        socket
      ) do
    {:noreply, stream_insert(socket, :lecture_progress_collection, lecture_progress)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    lecture_progress = Learning.get_lecture_progress!(id)
    {:ok, _} = Learning.delete_lecture_progress(lecture_progress)

    {:noreply, stream_delete(socket, :lecture_progress_collection, lecture_progress)}
  end
end
