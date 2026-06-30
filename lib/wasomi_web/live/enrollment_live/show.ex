defmodule WasomiWeb.EnrollmentLive.Show do
  use WasomiWeb, :live_view

  alias Wasomi.Enrollments

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:enrollment, Enrollments.get_enrollment!(id))}
  end

  defp page_title(:show), do: "Show Enrollment"
  defp page_title(:edit), do: "Edit Enrollment"
end
