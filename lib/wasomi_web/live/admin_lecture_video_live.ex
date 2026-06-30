defmodule WasomiWeb.AdminLectureVideoLive do
  use WasomiWeb, :live_view

  alias Wasomi.{Catalog, Media}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    lecture = Catalog.get_lecture!(id)

    {:ok,
     socket
     |> assign(:page_title, "Upload lecture video")
     |> assign(:lecture, lecture)
     |> assign(:upload, nil)
     |> assign(:upload_state, :idle)
     |> assign(:upload_message, nil)}
  end

  @impl true
  def handle_event("create-upload", _params, socket) do
    case Media.create_upload(socket.assigns.current_user, socket.assigns.lecture) do
      {:ok, upload} ->
        {:noreply,
         socket
         |> assign(:upload, upload)
         |> assign(:upload_state, :uploading)
         |> assign(:upload_message, "Uploading directly to Mux…")
         |> push_event("mux-upload-ready", %{url: upload.url})}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:upload_state, :error)
         |> assign(:upload_message, "Could not start upload: #{inspect(reason)}")}
    end
  end

  def handle_event("upload-complete", _params, socket) do
    {:noreply,
     socket
     |> assign(:upload_state, :processing)
     |> assign(:upload_message, "Upload complete. Mux is preparing protected playback…")
     |> push_event("mux-check-upload", %{})}
  end

  def handle_event("check-upload", _params, %{assigns: %{upload: %{id: upload_id}}} = socket) do
    case Media.upload_status(socket.assigns.current_user, upload_id) do
      {:ok, {:ready, playback_id, duration_seconds}} ->
        case Catalog.update_lecture(socket.assigns.lecture, %{
               video_provider: :mux,
               video_asset_id: playback_id,
               duration_seconds: duration_seconds
             }) do
          {:ok, lecture} ->
            {:noreply,
             socket
             |> assign(:lecture, lecture)
             |> assign(:upload_state, :ready)
             |> assign(:upload_message, "Video is ready for protected playback.")
             |> put_flash(:info, "Lecture video uploaded successfully")}

          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(:upload_state, :error)
             |> assign(:upload_message, "Video is ready, but the lecture could not be updated.")
             |> put_flash(:error, inspect(changeset.errors))}
        end

      {:ok, status} when status in [:waiting, :processing] ->
        {:noreply,
         socket
         |> assign(:upload_state, :processing)
         |> assign(:upload_message, "Mux is still processing the video…")
         |> push_event("mux-check-upload", %{})}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:upload_state, :error)
         |> assign(:upload_message, "Mux could not process this upload: #{inspect(reason)}")}
    end
  end

  def handle_event("check-upload", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-soft py-12">
      <div class="mx-auto max-w-3xl px-5 lg:px-8">
        <.link navigate={~p"/"} class="text-sm font-medium text-primary hover:text-dark">
          ← Back to Wasomi
        </.link>

        <section class="mt-6 rounded-3xl border border-black/5 bg-white p-6 shadow-lg sm:p-10">
          <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
            Admin · Mux direct upload
          </span>
          <h1 class="mt-5 text-3xl font-semibold text-dark">{@lecture.title}</h1>
          <p class="mt-3 text-body">
            The file travels straight from this browser to Mux. Wasomi stores only the signed
            playback ID after processing completes.
          </p>

          <div id="mux-upload" phx-hook="MuxUpload" class="mt-8">
            <label class="block text-sm font-medium text-dark" for="lecture-video">
              Video file
            </label>
            <input
              id="lecture-video"
              data-role="file"
              type="file"
              accept="video/*"
              class="mt-2 block w-full rounded-2xl border border-black/10 bg-white text-sm text-body file:mr-4 file:rounded-full file:border-0 file:bg-mint file:px-4 file:py-2 file:font-medium file:text-primary"
            />

            <div class="mt-5 h-2 overflow-hidden rounded-full bg-soft">
              <div data-role="progress" class="h-full w-0 rounded-full bg-primary transition-all">
              </div>
            </div>

            <button
              data-role="start"
              type="button"
              disabled={@upload_state in [:uploading, :processing]}
              class="mt-6 rounded-full bg-dark px-6 py-3 font-medium text-white transition hover:bg-primary disabled:cursor-not-allowed disabled:opacity-50"
            >
              Upload to Mux
            </button>
          </div>

          <p
            :if={@upload_message}
            id="upload-status"
            class={[
              "mt-5 rounded-2xl px-4 py-3 text-sm",
              @upload_state == :error && "bg-red-50 text-red-700",
              @upload_state == :ready && "bg-mint text-primary",
              @upload_state not in [:error, :ready] && "bg-soft text-body"
            ]}
          >
            {@upload_message}
          </p>

          <dl class="mt-8 grid gap-4 rounded-2xl border border-black/5 p-5 text-sm sm:grid-cols-2">
            <div>
              <dt class="text-muted">Provider</dt>
              <dd class="mt-1 font-medium text-dark">{@lecture.video_provider}</dd>
            </div>
            <div>
              <dt class="text-muted">Protected playback ID</dt>
              <dd class="mt-1 break-all font-medium text-dark">{@lecture.video_asset_id}</dd>
            </div>
          </dl>
        </section>
      </div>
    </main>
    """
  end
end
