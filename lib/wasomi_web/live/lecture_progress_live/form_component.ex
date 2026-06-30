defmodule WasomiWeb.LectureProgressLive.FormComponent do
  use WasomiWeb, :live_component

  alias Wasomi.Learning

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage lecture_progress records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="lecture_progress-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          prompt="Choose a value"
          options={Ecto.Enum.values(Wasomi.Learning.LectureProgress, :status)}
        />
        <.input field={@form[:last_position_seconds]} type="number" label="Last position seconds" />
        <.input field={@form[:completed_at]} type="datetime-local" label="Completed at" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Lecture progress</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{lecture_progress: lecture_progress} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Learning.change_lecture_progress(lecture_progress))
     end)}
  end

  @impl true
  def handle_event("validate", %{"lecture_progress" => lecture_progress_params}, socket) do
    changeset =
      Learning.change_lecture_progress(socket.assigns.lecture_progress, lecture_progress_params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"lecture_progress" => lecture_progress_params}, socket) do
    save_lecture_progress(socket, socket.assigns.action, lecture_progress_params)
  end

  defp save_lecture_progress(socket, :edit, lecture_progress_params) do
    case Learning.update_lecture_progress(
           socket.assigns.lecture_progress,
           lecture_progress_params
         ) do
      {:ok, lecture_progress} ->
        notify_parent({:saved, lecture_progress})

        {:noreply,
         socket
         |> put_flash(:info, "Lecture progress updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_lecture_progress(socket, :new, lecture_progress_params) do
    case Learning.create_lecture_progress(lecture_progress_params) do
      {:ok, lecture_progress} ->
        notify_parent({:saved, lecture_progress})

        {:noreply,
         socket
         |> put_flash(:info, "Lecture progress created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
