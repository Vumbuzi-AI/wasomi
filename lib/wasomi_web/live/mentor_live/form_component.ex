defmodule WasomiWeb.MentorLive.FormComponent do
  use WasomiWeb, :live_component

  alias Wasomi.Mentors

  @max_photo_bytes 5_000_000

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage the mentors shown on the homepage.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="mentor-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        novalidate
      >
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:role]} type="text" label="Role / title" />
        <div class="hidden">
          <.input field={@form[:photo_key]} type="text" />
        </div>

        <div class="space-y-2">
          <span class="block text-sm font-semibold text-zinc-800">Photo</span>

          <label
            phx-drop-target={@uploads.photo.ref}
            class="group relative flex min-h-[160px] w-full cursor-pointer flex-col items-center justify-center overflow-hidden rounded-xl border border-dashed border-zinc-300 bg-zinc-50 p-3 transition hover:border-zinc-400 hover:bg-zinc-100/50"
          >
            <.live_file_input upload={@uploads.photo} class="sr-only" />

            <%= cond do %>
              <% entry = List.first(@uploads.photo.entries) -> %>
                <div class="relative h-44 w-full overflow-hidden rounded-lg bg-zinc-100">
                  <.live_img_preview entry={entry} class="h-full w-full object-cover" />
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-target={@myself}
                    phx-value-ref={entry.ref}
                    class="absolute top-2 right-2 z-10 rounded-full bg-black/70 p-1.5 text-white transition hover:bg-rose-600"
                    title="Remove photo"
                  >
                    <.icon name="hero-x-mark" class="h-4 w-4" />
                  </button>
                </div>
              <% photo_preview(@form[:photo_key].value) -> %>
                <div class="relative h-44 w-full overflow-hidden rounded-lg bg-zinc-100">
                  <img
                    src={photo_preview(@form[:photo_key].value)}
                    alt=""
                    class="h-full w-full object-cover"
                  />
                </div>
              <% true -> %>
                <div class="flex flex-col items-center justify-center py-4 text-center">
                  <.icon name="hero-photo" class="h-8 w-8 text-zinc-400" />
                  <p class="mt-2 text-sm font-medium text-zinc-700">
                    Click to select photo or drag and drop
                  </p>
                  <p class="mt-1 text-xs text-zinc-500">
                    JPG, PNG or WebP, up to 5 MB
                  </p>
                </div>
            <% end %>
          </label>

          <div :for={entry <- @uploads.photo.entries} class="space-y-1">
            <div :if={entry.progress > 0} class="h-2 overflow-hidden rounded-full bg-zinc-100">
              <div
                class="h-full rounded-full bg-dark transition-all"
                style={"width: #{entry.progress}%"}
              >
              </div>
            </div>
            <p
              :for={err <- upload_errors(@uploads.photo, entry)}
              class="text-sm font-medium text-rose-600"
            >
              {upload_error_to_string(err)}
            </p>
          </div>
        </div>

        <.input field={@form[:twitter_url]} type="text" label="X (Twitter) URL" />
        <.input field={@form[:facebook_url]} type="text" label="Facebook URL" />
        <.input field={@form[:linkedin_url]} type="text" label="LinkedIn URL" />
        <.input field={@form[:position]} type="number" label="Display order" min="1" />
        <.input field={@form[:is_active]} type="checkbox" label="Show on homepage" />

        <:actions>
          <.button phx-disable-with="Saving...">Save Mentor</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{mentor: mentor} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:form, fn ->
        to_form(Mentors.change_mentor(mentor))
      end)

    socket =
      if socket.assigns[:uploads] do
        socket
      else
        allow_upload(socket, :photo,
          accept: ~w(.jpg .jpeg .png .webp),
          max_entries: 1,
          max_file_size: @max_photo_bytes
        )
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"mentor" => mentor_params}, socket) do
    changeset = Mentors.change_mentor(socket.assigns.mentor, mentor_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"mentor" => mentor_params}, socket) do
    mentor_params = put_uploaded_photo(socket, mentor_params)
    save_mentor(socket, socket.assigns.action, mentor_params)
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  defp put_uploaded_photo(socket, params) do
    uploaded =
      consume_uploaded_entries(socket, :photo, fn %{path: tmp_path}, entry ->
        dir = Path.join(:code.priv_dir(:wasomi), "static/uploads/mentors")
        File.mkdir_p!(dir)
        filename = "#{entry.uuid}#{entry.client_name |> Path.extname() |> String.downcase()}"
        File.cp!(tmp_path, Path.join(dir, filename))
        {:ok, "/uploads/mentors/#{filename}"}
      end)

    case uploaded do
      [url | _] -> Map.put(params, "photo_key", url)
      [] -> params
    end
  end

  defp save_mentor(socket, :edit, mentor_params) do
    case Mentors.update_mentor(socket.assigns.mentor, mentor_params) do
      {:ok, mentor} ->
        notify_parent({:saved, mentor})

        {:noreply,
         socket
         |> put_flash(:info, "Mentor updated successfully")
         |> push_patch(to: socket.assigns.patch.(mentor))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_mentor(socket, :new, mentor_params) do
    case Mentors.create_mentor(mentor_params) do
      {:ok, mentor} ->
        notify_parent({:saved, mentor})

        {:noreply,
         socket
         |> put_flash(:info, "Mentor created successfully")
         |> push_patch(to: socket.assigns.patch.(mentor))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp photo_preview(value) when is_binary(value) and value != "", do: value
  defp photo_preview(_value), do: nil

  defp upload_error_to_string(:too_large), do: "That image is larger than the 5 MB limit."
  defp upload_error_to_string(:not_accepted), do: "Please choose a JPG, PNG or WebP image."
  defp upload_error_to_string(:too_many_files), do: "You can only attach one photo."
  defp upload_error_to_string(_), do: "Could not accept that image."

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
