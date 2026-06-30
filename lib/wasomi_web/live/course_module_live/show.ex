defmodule WasomiWeb.CourseModuleLive.Show do
  use WasomiWeb, :live_view

  alias Wasomi.Catalog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:course_module, Catalog.get_course_module!(id))}
  end

  defp page_title(:show), do: "Show Course module"
  defp page_title(:edit), do: "Edit Course module"
end
