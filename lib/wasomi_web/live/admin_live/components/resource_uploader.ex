defmodule WasomiWeb.AdminLive.Components.ResourceUploader do
  use WasomiWeb, :live_component

  alias Wasomi.Storage

  @accepted_extensions ~w(.pdf .zip .pptx .docx)
  @max_file_size 50 * 1_000_000

  def configure_upload(socket, lecture_id) do
    prefix = lecture_id || "draft-#{Ecto.UUID.generate()}"

    allow_upload(socket, :resources,
      accept: @accepted_extensions,
      max_entries: 20,
      max_file_size: @max_file_size,
      auto_upload: true,
      external: fn entry, upload_socket -> presign_entry(entry, upload_socket, prefix) end
    )
  end

  attr :id, :string, default: "resource-uploader"
  attr :current_user, :map, required: true
  attr :upload_config, :map, required: true
  attr :target, :any, required: true
  attr :title, :string, default: "Learning resources"
  attr :description, :string, default: "Drop files here or browse from your computer."

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="space-y-4" phx-drop-target={@upload_config.ref}>
      <div class="group rounded-2xl border-2 border-dashed border-primary/40 bg-mint/30 p-6 text-center transition hover:border-primary hover:bg-mint/50">
        <.icon name="hero-cloud-arrow-up" class="mx-auto h-9 w-9 text-primary" />
        <h3 class="mt-3 font-semibold text-ink">{@title}</h3>
        <p class="mt-1 text-sm text-muted">{@description}</p>
        <p class="mt-2 text-xs text-muted">PDF, ZIP, PPTX or DOCX · up to 50 MB each</p>
        <label class="mt-4 inline-flex cursor-pointer items-center gap-2 rounded-full bg-ink px-4 py-2.5 text-sm font-medium text-white transition hover:bg-primary">
          <.icon name="hero-folder-open" class="h-4 w-4" /> Choose files
          <.live_file_input upload={@upload_config} class="sr-only" />
        </label>
      </div>

      <div :if={@upload_config.entries == []} class="text-center text-xs text-muted">
        Files are uploaded directly to secure storage; they are never buffered in Wasomi.
      </div>

      <ul :if={@upload_config.entries != []} class="space-y-2" aria-live="polite">
        <li
          :for={entry <- @upload_config.entries}
          id={"resource-upload-#{entry.ref}"}
          class="flex items-center gap-3 rounded-xl border border-black/5 bg-white p-3"
        >
          <span class="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-neutral-50 text-primary">
            <.icon name={file_icon(entry.client_name)} class="h-5 w-5" />
          </span>
          <div class="min-w-0 flex-1">
            <div class="flex items-center justify-between gap-3">
              <p class="truncate text-sm font-medium text-ink">{entry.client_name}</p>
              <span class="shrink-0 text-xs tabular-nums text-muted">{entry.progress}%</span>
            </div>
            <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-neutral-50">
              <div
                class="h-full rounded-full bg-primary transition-[width]"
                style={"width: #{entry.progress}%"}
                role="progressbar"
                aria-valuemin="0"
                aria-valuemax="100"
                aria-valuenow={entry.progress}
              >
              </div>
            </div>
            <p :for={error <- upload_errors(@upload_config, entry)} class="mt-1 text-xs text-rose-600">
              {upload_error_to_string(error)}
            </p>
          </div>
          <button
            type="button"
            phx-click="cancel-upload"
            phx-target={@target}
            phx-value-ref={entry.ref}
            aria-label={"Remove #{entry.client_name}"}
            class="grid h-8 w-8 shrink-0 place-items-center rounded-full text-muted transition hover:bg-rose-50 hover:text-rose-600"
          >
            <.icon name="hero-x-mark" class="h-4 w-4" />
          </button>
        </li>
      </ul>

      <p :if={@upload_config.errors != []} class="text-sm text-rose-600">
        {upload_error_to_string(List.first(@upload_config.errors))}
      </p>
    </section>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:title, fn -> "Learning resources" end)
     |> assign_new(:description, fn -> "Drop files here or browse from your computer." end)}
  end

  defp presign_entry(entry, socket, prefix) do
    attrs = %{
      "filename" => entry.client_name,
      "content_type" => entry.client_type,
      "size" => entry.client_size
    }

    with :ok <- validate_extension(entry.client_name),
         :ok <- validate_content_type(entry.client_name, entry.client_type),
         {:ok, upload} <-
           Storage.presign_upload(socket.assigns.current_user, Map.put(attrs, "prefix", prefix)) do
      {:ok,
       %{
         uploader: "R2",
         url: upload.url,
         key: upload.key,
         public_url: upload.public_url,
         content_type: upload.content_type
       }, socket}
    else
      {:error, reason} -> {:error, %{reason: upload_error_to_string(reason)}, socket}
    end
  end

  defp validate_extension(filename) do
    if (Path.extname(filename) |> String.downcase()) in @accepted_extensions,
      do: :ok,
      else: {:error, :not_accepted}
  end

  defp validate_content_type(filename, content_type) do
    expected =
      case Path.extname(filename) |> String.downcase() do
        ".pdf" -> ["application/pdf"]
        ".zip" -> ["application/zip", "application/x-zip-compressed"]
        ".pptx" -> ["application/vnd.openxmlformats-officedocument.presentationml.presentation"]
        ".docx" -> ["application/vnd.openxmlformats-officedocument.wordprocessingml.document"]
        _ -> []
      end

    if expected != [] and
         (content_type in expected or content_type in [nil, "", "application/octet-stream"]) do
      :ok
    else
      {:error, :unsupported_content_type}
    end
  end

  defp file_icon(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".pdf" -> "hero-document-text"
      ".zip" -> "hero-archive-box"
      ".pptx" -> "hero-presentation-chart-bar"
      ".docx" -> "hero-document"
      _ -> "hero-paper-clip"
    end
  end

  defp upload_error_to_string(:too_large), do: "Files must be 50 MB or smaller."

  defp upload_error_to_string(:not_accepted),
    do: "Only PDF, ZIP, PPTX and DOCX files are accepted."

  defp upload_error_to_string(:unsupported_content_type), do: "That file type is not supported."
  defp upload_error_to_string(:document_too_large), do: "Files must be 50 MB or smaller."
  defp upload_error_to_string(:forbidden), do: "You are not allowed to upload resources."

  defp upload_error_to_string(:external_client_failure),
    do:
      "The direct upload was blocked. Confirm that R2 CORS allows PUT and the Content-Type header from this site."

  defp upload_error_to_string(:r2_not_configured),
    do: "R2 storage credentials are not configured on this server."

  defp upload_error_to_string(message) when is_binary(message), do: message
  defp upload_error_to_string(_), do: "Could not prepare this upload."
end
