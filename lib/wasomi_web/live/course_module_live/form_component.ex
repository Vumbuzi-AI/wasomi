defmodule WasomiWeb.CourseModuleLive.FormComponent do
  use WasomiWeb, :live_component

  alias Wasomi.Catalog

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Modules group related lectures within a course.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="course_module-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:description]} type="text" label="Description" />
        <.input field={@form[:position]} type="number" label="Position" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Course module</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{course_module: course_module} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Catalog.change_course_module(course_module))
     end)}
  end

  @impl true
  def handle_event("validate", %{"course_module" => course_module_params}, socket) do
    changeset = Catalog.change_course_module(socket.assigns.course_module, course_module_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"course_module" => course_module_params}, socket) do
    save_course_module(socket, socket.assigns.action, course_module_params)
  end

  defp save_course_module(socket, :edit, course_module_params) do
    case Catalog.update_course_module(socket.assigns.course_module, course_module_params) do
      {:ok, course_module} ->
        notify_parent({:saved, course_module})

        {:noreply,
         socket
         |> put_flash(:info, "Course module updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_course_module(socket, :new, course_module_params) do
    course_module_params =
      Map.put(course_module_params, "course_id", socket.assigns.course_module.course_id)

    case Catalog.create_course_module(course_module_params) do
      {:ok, course_module} ->
        notify_parent({:saved, course_module})

        {:noreply,
         socket
         |> put_flash(:info, "Course module created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
