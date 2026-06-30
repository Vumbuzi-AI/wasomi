defmodule WasomiWeb.EnrollmentLive.FormComponent do
  use WasomiWeb, :live_component

  alias Wasomi.Enrollments

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage enrollment records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="enrollment-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          prompt="Choose a value"
          options={Ecto.Enum.values(Wasomi.Enrollments.Enrollment, :status)}
        />
        <.input field={@form[:enrolled_at]} type="datetime-local" label="Enrolled at" />
        <.input field={@form[:activated_at]} type="datetime-local" label="Activated at" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Enrollment</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{enrollment: enrollment} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Enrollments.change_enrollment(enrollment))
     end)}
  end

  @impl true
  def handle_event("validate", %{"enrollment" => enrollment_params}, socket) do
    changeset = Enrollments.change_enrollment(socket.assigns.enrollment, enrollment_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"enrollment" => enrollment_params}, socket) do
    save_enrollment(socket, socket.assigns.action, enrollment_params)
  end

  defp save_enrollment(socket, :edit, enrollment_params) do
    case Enrollments.update_enrollment(socket.assigns.enrollment, enrollment_params) do
      {:ok, enrollment} ->
        notify_parent({:saved, enrollment})

        {:noreply,
         socket
         |> put_flash(:info, "Enrollment updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_enrollment(socket, :new, enrollment_params) do
    case Enrollments.create_enrollment(enrollment_params) do
      {:ok, enrollment} ->
        notify_parent({:saved, enrollment})

        {:noreply,
         socket
         |> put_flash(:info, "Enrollment created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
