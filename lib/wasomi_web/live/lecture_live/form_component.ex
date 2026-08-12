defmodule WasomiWeb.LectureLive.FormComponent do
  use WasomiWeb, :live_component

  require Logger

  alias Wasomi.{Catalog, Media, Storage}
  alias WasomiWeb.AdminLive.Components.ResourceUploader

  @impl true
  def render(assigns) do
    ~H"""
    <div id="lecture-form-component">
      <.header>
        {@title}
        <:subtitle>
          Add the lecture content, supporting resources, and common learner questions.
        </:subtitle>
      </.header>

      <%!-- Associated via the `form` attribute below rather than nested inside
    .simple_form's own <form> — nested <form> elements are invalid HTML and
    get silently dropped by the browser's parser on parse. Keeping this one
    as a real, separate <form> (rather than a plain div + phx-change-synced
    assign) means "Save link" always submits whatever is actually in the
    input at the moment of the click, with no server round-trip in between
    to go stale. --%>
      <form id="add-link-form" phx-submit="add-link" phx-target={@myself} class="hidden"></form>

      <.simple_form
        for={@form}
        id="lecture-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Title" required />
        <.input field={@form[:description]} type="textarea" label="Description" rows="4" required />

        <section
          id="lecture-video"
          class="space-y-4 rounded-2xl border border-black/5 bg-soft/40 p-4 sm:p-5"
        >
          <div>
            <h3 class="font-semibold text-dark">Lecture video</h3>
            <p class="mt-1 text-sm text-muted">
              The file uploads directly to Mux. Wasomi stores only the signed playback ID once
              processing is complete.
            </p>
          </div>

          <div
            id="lecture-video-upload"
            phx-hook="MuxUpload"
            phx-target={@myself}
            class="group relative rounded-2xl border-2 border-dashed border-black/10 bg-white p-6 text-center transition-colors hover:border-primary"
          >
            <input
              id="lecture-video-file"
              data-role="file"
              type="file"
              accept="video/*"
              class={[
                "absolute inset-0 h-full w-full cursor-pointer opacity-0",
                @video_upload_state != :idle && "pointer-events-none"
              ]}
            />

            <div :if={@video_upload_state == :idle} class="space-y-2">
              <.icon name="hero-arrow-up-tray" class="mx-auto h-6 w-6 text-muted" />
              <p class="text-sm font-medium text-dark">Drop a video here, or click to choose one</p>
              <p class="text-xs text-muted">MP4, MOV or WebM</p>
            </div>

            <div :if={@video_upload_state != :idle} class="space-y-3">
              <button
                type="button"
                phx-click="remove-video"
                phx-target={@myself}
                aria-label="Remove selected video"
                class="pointer-events-auto absolute right-3 top-3 flex h-6 w-6 items-center justify-center rounded-full bg-dark text-white opacity-0 transition-[opacity,transform] duration-150 ease-out hover:bg-rose-600 group-hover:opacity-100 active:scale-[0.96]"
              >
                <.icon name="hero-x-mark" class="h-4 w-4" />
              </button>

              <div class="flex items-center justify-center gap-3">
                <div class="relative h-16 w-28 shrink-0 overflow-hidden rounded-lg bg-black">
                  <img
                    :if={@video_thumbnail_url || @video_local_preview_url}
                    data-role="thumbnail"
                    src={@video_thumbnail_url || @video_local_preview_url}
                    class="animate-fade-in h-full w-full object-cover outline outline-1 -outline-offset-1 outline-black/10"
                  />
                  <div
                    :if={
                      is_nil(@video_thumbnail_url) and is_nil(@video_local_preview_url) and
                        @video_upload_state in [:uploading, :processing]
                    }
                    class="absolute inset-0 flex animate-pulse items-center justify-center bg-white/10"
                  >
                    <.icon name="hero-arrow-path" class="h-5 w-5 animate-spin text-muted" />
                  </div>
                </div>
                <div class="min-w-0 flex-1 text-left">
                  <p class="truncate text-sm font-medium text-dark">{@video_filename}</p>
                  <p class="text-xs text-muted">{format_file_size(@video_size)}</p>
                </div>
              </div>

              <div
                :if={@video_upload_state != :ready}
                class="h-2 overflow-hidden rounded-full bg-soft"
              >
                <div
                  data-role="progress"
                  class="h-full w-0 rounded-full bg-primary transition-[width] duration-150 ease-out"
                >
                </div>
              </div>
            </div>
          </div>

          <p
            :if={@video_upload_message}
            class={[
              "rounded-xl px-4 py-3 text-sm",
              @video_upload_state == :error && "bg-rose-50 text-rose-700",
              @video_upload_state == :ready && "bg-mint text-primary",
              @video_upload_state not in [:error, :ready] && "bg-white text-muted"
            ]}
          >
            {@video_upload_message}
          </p>
        </section>

        <section
          id="lecture-resources"
          class="space-y-4 rounded-2xl border border-black/5 bg-white p-4 sm:p-5"
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h3 class="font-semibold text-dark">Resources</h3>
              <p class="mt-1 text-sm text-muted">
                Add documents, videos, or useful links for learners.
              </p>
            </div>
            <div
              class="flex rounded-full border border-black/10 bg-soft p-1"
              role="group"
              aria-label="Resource type"
            >
              <button
                type="button"
                phx-click="set-resource-mode"
                phx-target={@myself}
                phx-value-mode="upload"
                data-role="resource-mode"
                data-mode="upload"
                aria-pressed={to_string(@resource_mode == :upload)}
                class={[
                  "rounded-full px-3 py-1.5 text-xs font-semibold transition",
                  if(@resource_mode == :upload,
                    do: "bg-dark text-white",
                    else: "text-muted hover:text-dark"
                  )
                ]}
              >
                Upload files
              </button>
              <button
                type="button"
                phx-click="set-resource-mode"
                phx-target={@myself}
                phx-value-mode="link"
                data-role="resource-mode"
                data-mode="link"
                aria-pressed={to_string(@resource_mode == :link)}
                class={[
                  "rounded-full px-3 py-1.5 text-xs font-semibold transition",
                  if(@resource_mode == :link,
                    do: "bg-dark text-white",
                    else: "text-muted hover:text-dark"
                  )
                ]}
              >
                Add link
              </button>
            </div>
          </div>
          <div
            data-role="resource-panel"
            data-mode="upload"
            class={@resource_mode != :upload && "hidden"}
          >
            <.live_component
              module={ResourceUploader}
              id="lecture-resource-uploader"
              current_user={@current_user}
              upload_config={@uploads.resources}
              target={@myself}
            />
          </div>

          <div data-role="resource-panel" data-mode="link" class={@resource_mode != :link && "hidden"}>
            <div id="add-link-fields" class="flex gap-3">
              <input
                id={"add-link-url-#{@resource_link_reset}"}
                name="url"
                type="url"
                form="add-link-form"
                required
                placeholder="https://example.com/reading"
                class="w-full min-w-0 flex-1 rounded-xl border border-black/10 bg-white px-3 py-2.5 text-sm text-dark focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />
              <button
                type="submit"
                form="add-link-form"
                class="shrink-0 rounded-xl border border-primary px-4 py-2.5 text-sm font-medium text-primary hover:bg-mint"
              >
                Save link
              </button>
            </div>
          </div>

          <div
            :if={@resource_rows == []}
            class="rounded-xl border border-dashed border-black/10 p-5 text-center text-sm text-muted"
          >
            No resources added yet.
          </div>
          <ul :if={@resource_rows != []} class="space-y-2">
            <li
              :for={{resource, index} <- Enum.with_index(@resource_rows)}
              id={"lecture-resource-#{resource_key(resource, index)}"}
              class="relative flex items-start gap-3 rounded-xl border border-black/5 bg-soft px-3 py-2.5 pr-10"
            >
              <span class="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white text-primary">
                <.icon name={resource_icon(resource.kind)} class="h-4 w-4" />
              </span>
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-medium text-dark">{resource.name}</p>
                <p class="truncate text-xs text-muted">
                  {resource.content_type || resource.url}
                </p>
                <div
                  :if={resource_status(resource) == :uploading}
                  class="mt-2 flex items-center gap-2"
                >
                  <div class="h-1.5 w-40 overflow-hidden rounded-full bg-black/10">
                    <div class="h-full w-1/3 animate-pulse rounded-full bg-primary"></div>
                  </div>
                  <span class="text-xs text-muted">Uploading…</span>
                </div>
                <p :if={resource_status(resource) == :error} class="mt-1 text-xs text-rose-600">
                  {resource[:error] || "Upload failed."}
                </p>
              </div>
              <button
                type="button"
                phx-click="remove-resource"
                phx-target={@myself}
                phx-value-index={index}
                aria-label={"Remove #{resource.name}"}
                class="absolute right-2 top-2 grid h-6 w-6 shrink-0 place-items-center rounded-full text-muted transition hover:bg-rose-50 hover:text-rose-600"
              >
                <.icon name="hero-x-mark" class="h-3.5 w-3.5" />
              </button>
            </li>
          </ul>
          <p :if={@resource_error} class="text-sm text-rose-600">{@resource_error}</p>
        </section>

        <section class="space-y-4 rounded-2xl border border-black/5 bg-white p-4 sm:p-5">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h3 class="font-semibold text-dark">Common learner questions</h3>
              <p class="mt-1 text-sm text-muted">
                Answer questions learners are likely to ask before or during the lecture.
              </p>
            </div>
            <button
              type="button"
              phx-click="add-question"
              phx-target={@myself}
              class="rounded-full border border-primary px-4 py-2 text-sm font-medium text-primary hover:bg-mint"
            >
              Add question
            </button>
          </div>

          <div
            :if={@question_rows == []}
            class="rounded-xl border border-dashed border-black/10 p-5 text-center text-sm text-muted"
          >
            No questions added yet.
          </div>
          <div
            :for={{question, index} <- Enum.with_index(@question_rows)}
            class="rounded-xl border border-black/5 bg-soft/40 p-3 sm:p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <p class="text-sm font-semibold text-dark">Question {index + 1}</p>
              <button
                type="button"
                phx-click="remove-question"
                phx-target={@myself}
                phx-value-index={index}
                class="text-sm font-medium text-rose-600 hover:text-rose-700"
              >
                Remove
              </button>
            </div>
            <div class="mt-3 space-y-3">
              <input
                name={"questions[#{index}][question]"}
                value={question.question}
                placeholder="What should learners know?"
                required
                class="w-full rounded-xl border border-black/10 bg-white px-3 py-2.5 text-sm text-dark focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />
              <textarea
                name={"questions[#{index}][answer]"}
                rows="3"
                placeholder="Write a clear answer..."
                required
                class="w-full rounded-xl border border-black/10 bg-white px-3 py-2.5 text-sm text-dark focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              >{question.answer}</textarea>
            </div>
          </div>
        </section>

        <:actions>
          <p
            :if={save_disabled?(@form, @resource_rows, @question_rows, @video_ready)}
            class="text-sm text-amber-700"
          >
            Upload a video and finish all resource uploads before saving.
          </p>
          <.button
            disabled={save_disabled?(@form, @resource_rows, @question_rows, @video_ready)}
            phx-disable-with="Saving..."
          >
            Save Lecture
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  defp consume_resource_uploads(socket) do
    case uploaded_entries(socket, :resources) do
      {_done, [_ | _]} ->
        assign(socket, :resource_error, "Finish or remove all resource uploads before saving.")

      {[], []} ->
        socket

      {_done, []} ->
        rows =
          consume_uploaded_entries(socket, :resources, fn meta, entry ->
            {:ok,
             %{
               kind: :document,
               name: entry.client_name,
               storage_key: meta.key,
               url: meta.public_url,
               content_type: meta.content_type || entry.client_type,
               byte_size: entry.client_size
             }}
          end)

        assign(socket, :resource_rows, socket.assigns.resource_rows ++ rows)
    end
  end

  @impl true
  def update(%{lecture: lecture} = assigns, socket) do
    lecture =
      if lecture.id, do: preload_content(lecture), else: %{lecture | resources: [], questions: []}

    existing_video_ready = existing_video_ready(lecture)

    socket =
      socket
      |> assign(assigns)
      |> assign(:lecture, lecture)
      |> assign_new(:form, fn -> to_form(Catalog.change_lecture(lecture)) end)
      |> assign_new(:resource_rows, fn -> Enum.map(lecture.resources || [], &resource_attrs/1) end)
      |> assign_new(:question_rows, fn -> Enum.map(lecture.questions || [], &question_attrs/1) end)
      |> assign_new(:resource_error, fn -> nil end)
      |> assign_new(:resource_mode, fn -> :upload end)
      |> assign_new(:resource_link_reset, fn -> 0 end)
      |> assign_new(:video_upload, fn -> nil end)
      |> assign_new(:video_upload_state, fn ->
        if existing_video_ready, do: :ready, else: :idle
      end)
      |> assign_new(:video_upload_message, fn -> nil end)
      |> assign_new(:video_ready, fn -> existing_video_ready end)
      |> assign_new(:video_thumbnail_url, fn ->
        case existing_video_ready do
          %{video_asset_id: playback_id} ->
            resolve_thumbnail_url(assigns.current_user, playback_id)

          nil ->
            nil
        end
      end)
      |> assign_new(:video_local_preview_url, fn -> nil end)
      |> assign_new(:video_filename, fn -> existing_video_ready && "Current video" end)
      |> assign_new(:video_size, fn -> nil end)

    socket =
      if Map.has_key?(socket.assigns, :uploads) and
           Map.has_key?(socket.assigns.uploads, :resources) do
        socket
      else
        ResourceUploader.configure_upload(socket, lecture.id)
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"lecture" => lecture_params} = params, socket) do
    questions = question_params(params)
    changeset = Catalog.change_lecture(socket.assigns.lecture, lecture_params)

    question_rows =
      if Map.has_key?(params, "questions"), do: questions, else: socket.assigns.question_rows

    {:noreply,
     assign(socket,
       form: to_form(changeset, action: :validate),
       question_rows: question_rows
     )}
  end

  def handle_event("add-link", %{"url" => url}, socket) do
    url = String.trim(url)

    if valid_url?(url) do
      row = %{
        kind: :link,
        name: url,
        url: url,
        storage_key: nil,
        content_type: nil,
        byte_size: nil,
        row_id: Ecto.UUID.generate()
      }

      {:noreply,
       socket
       |> update(:resource_link_reset, &(&1 + 1))
       |> assign(resource_rows: socket.assigns.resource_rows ++ [row], resource_error: nil)}
    else
      {:noreply, assign(socket, resource_error: "Enter a valid http or https link.")}
    end
  end

  def handle_event("add-link", _params, socket), do: {:noreply, socket}

  def handle_event("set-resource-mode", %{"mode" => "link"}, socket) do
    {:noreply, assign(socket, :resource_mode, :link)}
  end

  def handle_event("set-resource-mode", %{"mode" => _mode}, socket) do
    {:noreply, assign(socket, :resource_mode, :upload)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    meta = socket.assigns.uploads.resources.entry_refs_to_metas[ref] || %{}
    socket = cancel_upload(socket, :resources, ref)

    case meta[:key] do
      key when is_binary(key) and key != "" ->
        case Storage.delete_upload(socket.assigns.current_user, key) do
          :ok -> {:noreply, socket}
          {:error, reason} -> {:noreply, assign(socket, resource_error: upload_error(reason))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove-resource", %{"index" => index}, socket) do
    case resource_at(socket.assigns.resource_rows, index) do
      {:ok, %{storage_key: key}} when is_binary(key) and key != "" ->
        case Storage.delete_upload(socket.assigns.current_user, key) do
          :ok ->
            {:noreply,
             assign(socket, resource_rows: remove_at(socket.assigns.resource_rows, index))}

          {:error, reason} ->
            {:noreply, assign(socket, resource_error: upload_error(reason))}
        end

      _ ->
        {:noreply, assign(socket, resource_rows: remove_at(socket.assigns.resource_rows, index))}
    end
  end

  def handle_event("add-question", _params, socket) do
    {:noreply,
     assign(socket, question_rows: socket.assigns.question_rows ++ [%{question: "", answer: ""}])}
  end

  def handle_event("remove-question", %{"index" => index}, socket) do
    {:noreply, assign(socket, question_rows: remove_at(socket.assigns.question_rows, index))}
  end

  def handle_event("create-upload", params, socket) do
    socket =
      socket
      |> assign(:video_filename, normalize_filename(params["filename"]))
      |> assign(:video_size, normalize_size(params["size"]))

    case safe_media_call(fn ->
           Media.create_upload(socket.assigns.current_user, socket.assigns.lecture, [])
         end) do
      {:ok, upload} ->
        {:noreply,
         socket
         |> assign(:video_upload, upload)
         |> assign(:video_upload_state, :uploading)
         |> assign(:video_upload_message, "Uploading directly to Mux…")
         |> push_event("mux-upload-ready", %{url: upload.url})}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:video_upload_state, :error)
         |> assign(
           :video_upload_message,
           "Could not start upload: #{video_error_message(reason)}"
         )}
    end
  end

  def handle_event("upload-complete", _params, socket) do
    {:noreply,
     socket
     |> assign(:video_upload_state, :processing)
     |> assign(:video_upload_message, "Upload complete. Mux is preparing protected playback…")
     |> push_event("mux-check-upload", %{})}
  end

  def handle_event("upload-failed", params, socket) do
    {:noreply,
     socket
     |> assign(:video_upload_state, :error)
     |> assign(:video_upload_message, upload_failure_message(params["status"]))}
  end

  def handle_event("remove-video", _params, socket) do
    {:noreply,
     socket
     |> assign(:video_upload, nil)
     |> assign(:video_upload_state, :idle)
     |> assign(:video_upload_message, nil)
     |> assign(:video_ready, nil)
     |> assign(:video_thumbnail_url, nil)
     |> assign(:video_local_preview_url, nil)
     |> assign(:video_filename, nil)
     |> assign(:video_size, nil)
     |> push_event("mux-reset", %{})}
  end

  def handle_event("local-preview", %{"data_url" => data_url}, socket) do
    {:noreply, assign(socket, :video_local_preview_url, data_url)}
  end

  def handle_event(
        "check-upload",
        _params,
        %{assigns: %{video_upload: %{id: upload_id}}} = socket
      ) do
    case safe_media_call(fn -> Media.upload_status(socket.assigns.current_user, upload_id) end) do
      {:ok, {:ready, playback_id, duration_seconds}} ->
        {:noreply,
         socket
         |> assign(:video_ready, %{
           video_provider: :mux,
           video_asset_id: playback_id,
           duration_seconds: duration_seconds
         })
         |> assign(:video_thumbnail_url, thumbnail_url(socket, playback_id))
         |> assign(:video_upload_state, :ready)
         |> assign(:video_upload_message, nil)}

      {:ok, status} when status in [:waiting, :processing] ->
        {:noreply,
         socket
         |> assign(:video_upload_state, :processing)
         |> assign(:video_upload_message, "Mux is still processing the video…")
         |> push_event("mux-check-upload", %{})}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:video_upload_state, :error)
         |> assign(
           :video_upload_message,
           "Mux could not process this upload: #{video_error_message(reason)}"
         )}
    end
  end

  def handle_event("check-upload", _params, socket), do: {:noreply, socket}

  def handle_event("save", %{"lecture" => lecture_params} = params, socket) do
    socket = consume_resource_uploads(socket)
    lecture_params = put_video_fields(socket, lecture_params)
    questions = question_params(params, socket.assigns.question_rows)

    case validate_resources(socket.assigns.resource_rows) do
      :ok ->
        result =
          if socket.assigns.action == :new do
            lecture_params =
              lecture_params
              |> Map.put("module_id", socket.assigns.lecture.module_id)
              |> Map.put("position", socket.assigns.lecture.position)

            Catalog.create_lecture_content(
              lecture_params,
              socket.assigns.resource_rows,
              questions
            )
          else
            Catalog.update_lecture_content(
              socket.assigns.lecture,
              lecture_params,
              socket.assigns.resource_rows,
              questions
            )
          end

        case result do
          {:ok, lecture} ->
            notify_parent({:saved, lecture})

            {:noreply,
             socket
             |> put_flash(
               :info,
               if(socket.assigns.action == :new,
                 do: "Lecture created successfully",
                 else: "Lecture updated successfully"
               )
             )
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, form: to_form(changeset, action: :validate))}

          {:error, _reason} ->
            {:noreply,
             assign(socket,
               resource_error: "Could not save this lecture. Check the highlighted fields."
             )}
        end

      {:error, message} ->
        {:noreply, assign(socket, resource_error: message)}
    end
  end

  defp preload_content(%{resources: resources, questions: questions} = lecture)
       when is_list(resources) and is_list(questions),
       do: %{
         lecture
         | resources: sort_by_position(resources),
           questions: sort_by_position(questions)
       }

  defp preload_content(lecture), do: Catalog.preload_lecture_content(lecture)

  defp sort_by_position(records), do: Enum.sort_by(records, & &1.position)

  defp thumbnail_url(socket, playback_id),
    do: resolve_thumbnail_url(socket.assigns.current_user, playback_id)

  defp resolve_thumbnail_url(current_user, playback_id) do
    lecture = %Catalog.Lecture{video_provider: :mux, video_asset_id: playback_id}

    case safe_media_call(fn -> Media.thumbnail_url(current_user, lecture) end) do
      {:ok, url} -> url
      {:error, _reason} -> nil
    end
  end

  defp existing_video_ready(%Catalog.Lecture{
         id: id,
         video_provider: :mux,
         video_asset_id: asset_id,
         duration_seconds: duration
       })
       when not is_nil(id) and is_binary(asset_id) and asset_id != "" do
    %{video_provider: :mux, video_asset_id: asset_id, duration_seconds: duration}
  end

  defp existing_video_ready(_lecture), do: nil

  defp safe_media_call(fun) do
    fun.()
  rescue
    error ->
      Logger.error(
        "Media call raised #{inspect(error.__struct__)}: #{Exception.message(error)}\n" <>
          Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, {:exception, Exception.message(error)}}
  end

  defp video_error_message(:forbidden),
    do: "you don't have permission to upload lecture videos."

  defp video_error_message(:media_provider_not_configured),
    do: "video uploads aren't configured on this server yet."

  defp video_error_message({:exception, message}), do: message

  defp video_error_message({:mux, %{"messages" => [_ | _] = messages}}),
    do: "Mux rejected the request (#{Enum.join(messages, " ")})"

  defp video_error_message({:mux, %{"type" => type}}), do: "Mux rejected the request (#{type})"

  defp video_error_message({:mux, status, _body}) when is_integer(status),
    do: "Mux returned an unexpected response (HTTP #{status})"

  defp video_error_message({:mux_asset_errored, errors}) when is_list(errors) do
    case errors |> Enum.flat_map(&Map.get(&1, "messages", [])) |> Enum.join(" ") do
      "" -> "Mux could not process this video"
      messages -> "Mux could not process this video (#{messages})"
    end
  end

  defp video_error_message(:mux_asset_has_no_signed_playback_id),
    do: "Mux processed the video but did not return a signed playback ID"

  defp video_error_message({:mux_upload_errored, _error}),
    do: "Mux reported that the upload failed — try selecting the file again"

  defp video_error_message({:invalid_mux_signing_key, message}),
    do:
      "the Mux signing key isn't configured correctly (MUX_SIGNING_KEY_ID / MUX_SIGNING_PRIVATE_KEY): #{message}"

  defp video_error_message(reason), do: inspect(reason)

  defp upload_failure_message(status) when is_integer(status),
    do: "The upload to Mux failed (HTTP #{status}). Remove it and try selecting the file again."

  defp upload_failure_message(_status),
    do:
      "The upload to Mux failed because of a network error. Remove it and try selecting the file again."

  defp normalize_filename(filename) when is_binary(filename) do
    case String.trim(filename) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 255)
    end
  end

  defp normalize_filename(_filename), do: nil

  defp normalize_size(size) when is_integer(size) and size >= 0, do: size
  defp normalize_size(size) when is_float(size) and size >= 0, do: trunc(size)
  defp normalize_size(_size), do: nil

  defp format_file_size(size) when is_number(size) and size > 0 do
    {value, unit} = scale_bytes(size / 1, ["B", "KB", "MB", "GB"])
    precision = if unit == "B", do: 0, else: 1
    :erlang.float_to_binary(value, decimals: precision) <> " " <> unit
  end

  defp format_file_size(_size), do: ""

  defp scale_bytes(value, [unit]), do: {value, unit}
  defp scale_bytes(value, [unit | _rest]) when value < 1024, do: {value, unit}
  defp scale_bytes(value, [_unit | rest]), do: scale_bytes(value / 1024, rest)

  defp put_video_fields(socket, params) do
    params = Map.put(params, "video_provider", "mux")

    case socket.assigns.video_ready do
      %{video_asset_id: asset_id, duration_seconds: duration} ->
        Map.merge(params, %{"video_asset_id" => asset_id, "duration_seconds" => duration})

      nil ->
        params
    end
  end

  defp resource_attrs(resource),
    do: Map.take(resource, [:id, :kind, :name, :storage_key, :url, :content_type, :byte_size])

  defp question_attrs(question), do: Map.take(question, [:question, :answer])

  defp resource_status(resource), do: Map.get(resource, :status, :ready)

  defp resource_icon(:document), do: "hero-document-text"
  defp resource_icon(:video), do: "hero-film"
  defp resource_icon(:link), do: "hero-link"

  defp resource_at(rows, index) do
    case parse_index(index) do
      {:ok, index} when index < length(rows) -> {:ok, Enum.at(rows, index)}
      _ -> :error
    end
  end

  defp validate_resources(resources) do
    if Enum.all?(resources, &resource_ready?/1) do
      :ok
    else
      {:error, "Finish or remove all resource uploads before saving."}
    end
  end

  defp resource_ready?(resource) do
    resource_status(resource) == :ready and
      is_binary(resource[:name]) and resource[:name] != "" and
      case resource[:kind] do
        :link ->
          valid_url?(resource[:url])

        kind when kind in [:document, :video] ->
          is_binary(resource[:storage_key]) and resource[:storage_key] != "" and
            is_binary(resource[:content_type]) and resource[:content_type] != "" and
            is_integer(resource[:byte_size]) and resource[:byte_size] > 0

        _ ->
          false
      end
  end

  defp resource_key(resource, index),
    do: resource[:id] || resource[:storage_key] || resource[:row_id] || index

  defp question_params(%{"questions" => questions}), do: normalize_questions(questions)
  defp question_params(_params), do: []

  defp question_params(params, fallback),
    do: if(Map.has_key?(params, "questions"), do: question_params(params), else: fallback)

  defp normalize_questions(questions) when is_map(questions) do
    questions
    |> Enum.sort_by(fn {index, _} -> parse_integer(index) end)
    |> Enum.map(fn {_index, attrs} -> normalize_question(attrs) end)
    |> Enum.reject(&(&1.question == "" and &1.answer == ""))
  end

  defp normalize_questions(_), do: []

  defp normalize_question(attrs) when is_map(attrs) do
    %{
      question: trim_param(attrs["question"]),
      answer: trim_param(attrs["answer"])
    }
  end

  defp normalize_question(_attrs), do: %{question: "", answer: ""}

  defp trim_param(value) when is_binary(value), do: String.trim(value)
  defp trim_param(_value), do: ""

  defp save_disabled?(form, resources, questions, video_ready) do
    required = [:title, :description, :position]

    Enum.any?(required, &blank?(form[&1].value)) or
      is_nil(video_ready) or
      Enum.any?(resources, &(resource_status(&1) in [:uploading, :error])) or
      Enum.any?(resources, &(blank?(&1[:name]) or (&1[:kind] == :link and !valid_url?(&1[:url])))) or
      Enum.any?(questions, &(blank?(&1[:question]) or blank?(&1[:answer])))
  end

  defp blank?(value), do: is_nil(value) or value == ""

  defp valid_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        true

      _ ->
        false
    end
  end

  defp valid_url?(_), do: false

  defp remove_at(rows, index) do
    case parse_index(index) do
      {:ok, index} ->
        Enum.with_index(rows)
        |> Enum.reject(fn {_row, row_index} -> row_index == index end)
        |> Enum.map(&elem(&1, 0))

      :error ->
        rows
    end
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {value, ""} -> value
      _ -> 0
    end
  end

  defp parse_integer(_), do: 0

  defp parse_index(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp parse_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {value, ""} when value >= 0 -> {:ok, value}
      _ -> :error
    end
  end

  defp parse_index(_), do: :error

  defp upload_error(:unsupported_content_type), do: "That file type is not supported."

  defp upload_error(:r2_not_configured),
    do:
      "R2 is not configured in the server process. Export the R2 variables, then restart Wasomi."

  defp upload_error(:invalid_upload_metadata),
    do: "The browser did not provide valid file metadata."

  defp upload_error(:invalid_file_size), do: "The file size could not be determined."
  defp upload_error(:document_too_large), do: "Documents must be 50 MB or smaller."
  defp upload_error(:video_too_large), do: "Videos must be 1 GB or smaller."

  defp upload_error(_),
    do: "R2 could not prepare that upload. Check the server log for the storage error."

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
