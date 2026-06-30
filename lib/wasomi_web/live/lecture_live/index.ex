defmodule WasomiWeb.LectureLive.Index do
  use WasomiWeb, :live_view

  alias Wasomi.Catalog
  alias Wasomi.Catalog.Lecture

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :lectures, Catalog.list_lectures())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Lecture")
    |> assign(:lecture, Catalog.get_lecture!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Lecture")
    |> assign(:lecture, %Lecture{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Lectures")
    |> assign(:lecture, nil)
  end

  @impl true
  def handle_info({WasomiWeb.LectureLive.FormComponent, {:saved, lecture}}, socket) do
    {:noreply, stream_insert(socket, :lectures, lecture)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    lecture = Catalog.get_lecture!(id)
    {:ok, _} = Catalog.delete_lecture(lecture)

    {:noreply, stream_delete(socket, :lectures, lecture)}
  end
end
