defmodule WasomiWeb.LectureLive.FormComponent do
  use WasomiWeb, :live_component

  alias Wasomi.Catalog

  @max_video_bytes 1_000_000_000

  @impl true
  def render(assigns) do
    ~H"""
    <div id="lecture-form-component">
      <.header>
        {@title}
        <:subtitle>A lecture is a single video within a module.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="lecture-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:description]} type="text" label="Description" />

        <%!-- Upload a video file, preview it, and save. --%>
        <div id="lecture-video" phx-hook="VideoPreview" class="space-y-3">
          <span class="block text-sm font-semibold leading-6 text-zinc-800">Lecture video</span>

          <video
            id="lecture-video-preview"
            phx-update="ignore"
            data-role="preview"
            src={preview_src(@form[:video_asset_id].value)}
            controls
            class={[
              "w-full rounded-lg border border-zinc-200 bg-black",
              !preview_src(@form[:video_asset_id].value) && "hidden"
            ]}
          >
          </video>

          <.live_file_input upload={@uploads.video} class="block w-full text-sm text-zinc-700" />

          <p class="text-xs text-zinc-500">
            MP4, MOV or WebM, up to 1 GB. The preview and duration update automatically once you pick a file.
          </p>

          <div :for={entry <- @uploads.video.entries} class="space-y-1">
            <div class="h-2 overflow-hidden rounded-full bg-zinc-100">
              <div
                class="h-full rounded-full bg-emerald-500 transition-all"
                style={"width: #{entry.progress}%"}
              >
              </div>
            </div>
            <p :for={err <- upload_errors(@uploads.video, entry)} class="text-sm text-rose-600">
              {upload_error_to_string(err)}
            </p>
          </div>

          <.error :for={msg <- Enum.map(@form[:video_asset_id].errors, &translate_error/1)}>
            {msg}
          </.error>
        </div>

        <.input field={@form[:duration_seconds]} type="number" label="Duration (seconds)" />
        <.input field={@form[:position]} type="number" label="Position" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Lecture</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{lecture: lecture} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:form, fn -> to_form(Catalog.change_lecture(lecture)) end)

    socket =
      if socket.assigns[:uploads] do
        socket
      else
        allow_upload(socket, :video,
          accept: ~w(.mp4 .mov .webm),
          max_entries: 1,
          max_file_size: @max_video_bytes
        )
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"lecture" => lecture_params}, socket) do
    changeset = Catalog.change_lecture(socket.assigns.lecture, lecture_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"lecture" => lecture_params}, socket) do
    lecture_params = put_uploaded_video(socket, lecture_params)
    save_lecture(socket, socket.assigns.action, lecture_params)
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :video, ref)}
  end

  # Persist any newly uploaded file to priv/static/uploads and point the lecture
  # at its public path. Provider is fixed to :mux so the player streams it directly.
  defp put_uploaded_video(socket, params) do
    uploaded =
      consume_uploaded_entries(socket, :video, fn %{path: tmp_path}, entry ->
        dir = Path.join(:code.priv_dir(:wasomi), "static/uploads/lectures")
        File.mkdir_p!(dir)
        filename = "#{entry.uuid}#{Path.extname(entry.client_name)}"
        File.cp!(tmp_path, Path.join(dir, filename))
        {:ok, "/uploads/lectures/#{filename}"}
      end)

    case uploaded do
      [url | _] -> Map.merge(params, %{"video_asset_id" => url, "video_provider" => "mux"})
      [] -> params
    end
  end

  defp save_lecture(socket, :edit, lecture_params) do
    case Catalog.update_lecture(socket.assigns.lecture, lecture_params) do
      {:ok, lecture} ->
        notify_parent({:saved, lecture})

        {:noreply,
         socket
         |> put_flash(:info, "Lecture updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_lecture(socket, :new, lecture_params) do
    lecture_params = Map.put(lecture_params, "module_id", socket.assigns.lecture.module_id)

    case Catalog.create_lecture(lecture_params) do
      {:ok, lecture} ->
        notify_parent({:saved, lecture})

        {:noreply,
         socket
         |> put_flash(:info, "Lecture created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # Only locally-uploaded files and plain video URLs are previewable in a <video>
  # element; HLS (.m3u8) seeds are not, so they fall back to "no preview".
  defp preview_src(value) when is_binary(value) do
    if String.starts_with?(value, "/uploads/") or
         (String.starts_with?(value, "http") and Path.extname(value) in ~w(.mp4 .mov .webm .m4v)) do
      value
    end
  end

  defp preview_src(_), do: nil

  defp upload_error_to_string(:too_large), do: "That file is larger than the 1 GB limit."
  defp upload_error_to_string(:not_accepted), do: "Please choose an MP4, MOV or WebM file."
  defp upload_error_to_string(:too_many_files), do: "You can only attach one video."
  defp upload_error_to_string(_), do: "Could not accept that file."

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
