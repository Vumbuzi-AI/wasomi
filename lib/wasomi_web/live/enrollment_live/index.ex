defmodule WasomiWeb.EnrollmentLive.Index do
  use WasomiWeb, :live_view

  alias Wasomi.Enrollments
  alias Wasomi.Enrollments.Enrollment

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :enrollments, Enrollments.list_enrollments())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Enrollment")
    |> assign(:enrollment, Enrollments.get_enrollment!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Enrollment")
    |> assign(:enrollment, %Enrollment{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Enrollments")
    |> assign(:enrollment, nil)
  end

  @impl true
  def handle_info({WasomiWeb.EnrollmentLive.FormComponent, {:saved, enrollment}}, socket) do
    {:noreply, stream_insert(socket, :enrollments, enrollment)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    enrollment = Enrollments.get_enrollment!(id)
    {:ok, _} = Enrollments.delete_enrollment(enrollment)

    {:noreply, stream_delete(socket, :enrollments, enrollment)}
  end
end
