defmodule WasomiWeb.LectureProgressLive.Show do
  use WasomiWeb, :live_view

  alias Wasomi.Learning

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:lecture_progress, Learning.get_lecture_progress!(id))}
  end

  defp page_title(:show), do: "Show Lecture progress"
  defp page_title(:edit), do: "Edit Lecture progress"
end
