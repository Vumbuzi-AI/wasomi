defmodule WasomiWeb.LectureLive.FormComponent do
  use WasomiWeb, :live_component

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

          <div id="lecture-video-upload" phx-hook="MuxUpload" phx-target={@myself}>
            <label class="block text-sm font-medium text-dark" for="lecture-video-file">
              Video file
            </label>
            <input
              id="lecture-video-file"
              data-role="file"
              type="file"
              accept="video/*"
              class="mt-2 block w-full rounded-2xl border border-black/10 bg-white text-sm text-body file:mr-4 file:rounded-full file:border-0 file:bg-mint file:px-4 file:py-2 file:font-medium file:text-primary"
            />

            <div class="mt-4 h-2 overflow-hidden rounded-full bg-soft">
              <div data-role="progress" class="h-full w-0 rounded-full bg-primary transition-all">
              </div>
            </div>

            <button
              data-role="start"
              type="button"
              disabled={@video_upload_state in [:uploading, :processing]}
              class="mt-4 inline-flex items-center gap-2 rounded-full bg-dark px-4 py-2.5 text-sm font-medium text-white transition hover:bg-primary disabled:cursor-not-allowed disabled:opacity-50"
            >
              <.icon name="hero-arrow-up-tray" class="h-4 w-4" /> Upload to Mux
            </button>
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

          <details class="rounded-xl border border-black/5 bg-white p-3 text-sm">
            <summary class="cursor-pointer font-medium text-dark">
              Advanced: use an existing Mux playback ID
            </summary>
            <div class="mt-3 grid gap-4 sm:grid-cols-2">
              <.input field={@form[:video_asset_id]} type="text" label="Video playback ID" />
              <.input
                field={@form[:duration_seconds]}
                type="number"
                label="Duration (seconds)"
                min="1"
              />
            </div>
          </details>
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
                data-role="resource-mode"
                data-mode="upload"
                aria-pressed="true"
                class="rounded-full bg-dark px-3 py-1.5 text-xs font-semibold text-white transition"
              >
                Upload files
              </button>
              <button
                type="button"
                data-role="resource-mode"
                data-mode="link"
                aria-pressed="false"
                class="rounded-full px-3 py-1.5 text-xs font-semibold text-muted transition hover:text-dark"
              >
                Add link
              </button>
            </div>
          </div>
          <div data-role="resource-panel" data-mode="upload">
            <.live_component
              module={ResourceUploader}
              id="lecture-resource-uploader"
              current_user={@current_user}
              upload_config={@uploads.resources}
              target={@myself}
            />
          </div>

          <div data-role="resource-panel" data-mode="link" class="hidden">
            <div class="grid gap-3 sm:grid-cols-[1fr_auto]">
              <input
                data-role="link"
                type="url"
                placeholder="https://example.com/reading"
                class="w-full rounded-xl border border-black/10 bg-white px-3 py-2.5 text-sm text-dark focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />
              <button
                data-role="add-link"
                type="button"
                class="rounded-xl border border-primary px-4 py-2.5 text-sm font-medium text-primary hover:bg-mint"
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
              class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-black/5 bg-soft px-3 py-2.5"
            >
              <div class="min-w-0">
                <p class="truncate text-sm font-medium text-dark">{resource.name}</p>
                <p class="text-xs capitalize text-muted">
                  {resource.kind} · {resource.content_type || resource.url}
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
                class="shrink-0 text-sm font-medium text-rose-600 hover:text-rose-700"
              >
                Remove
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
            Upload a video (or provide an existing Mux playback ID and duration), and finish all
            resource uploads before saving.
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

    socket =
      socket
      |> assign(assigns)
      |> assign(:lecture, lecture)
      |> assign_new(:form, fn -> to_form(Catalog.change_lecture(lecture)) end)
      |> assign_new(:resource_rows, fn -> Enum.map(lecture.resources || [], &resource_attrs/1) end)
      |> assign_new(:question_rows, fn -> Enum.map(lecture.questions || [], &question_attrs/1) end)
      |> assign_new(:resource_error, fn -> nil end)
      |> assign_new(:video_upload, fn -> nil end)
      |> assign_new(:video_upload_state, fn -> :idle end)
      |> assign_new(:video_upload_message, fn -> nil end)
      |> assign_new(:video_ready, fn -> nil end)

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
        byte_size: nil
      }

      {:noreply,
       assign(socket, resource_rows: socket.assigns.resource_rows ++ [row], resource_error: nil)}
    else
      {:noreply, assign(socket, resource_error: "Enter a valid http or https link.")}
    end
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

  def handle_event("add-link", _params, socket), do: {:noreply, socket}

  def handle_event("presign-resource", params, socket) do
    case Storage.presign_upload(socket.assigns.current_user, params) do
      {:ok, upload} ->
        pending = %{
          kind: upload.kind,
          name: params["filename"],
          url: nil,
          storage_key: nil,
          content_type: params["content_type"],
          byte_size: parse_integer(params["size"]),
          status: :uploading,
          client_ref: params["client_ref"]
        }

        {:noreply,
         socket
         |> assign(resource_rows: socket.assigns.resource_rows ++ [pending])
         |> push_event("r2-upload-ready", Map.put(upload, :client_ref, params["client_ref"]))}

      {:error, reason} ->
        {:noreply, assign(socket, :resource_error, upload_error(reason))}
    end
  end

  def handle_event("resource-uploaded", params, socket) do
    row = %{
      kind: string_to_kind(params["kind"]),
      name: params["name"],
      storage_key: params["key"],
      url: params["public_url"],
      content_type: params["content_type"],
      byte_size: parse_integer(params["byte_size"])
    }

    {:noreply,
     assign(socket,
       resource_rows:
         replace_pending_resource(socket.assigns.resource_rows, params["client_ref"], row),
       resource_error: nil
     )}
  end

  def handle_event(
        "resource-upload-failed",
        %{"client_ref" => client_ref, "message" => message},
        socket
      ) do
    {:noreply,
     assign(socket,
       resource_rows: mark_resource_error(socket.assigns.resource_rows, client_ref, message),
       resource_error: message
     )}
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

  def handle_event("create-upload", _params, socket) do
    case Media.create_upload(socket.assigns.current_user, socket.assigns.lecture, []) do
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
         |> assign(:video_upload_message, "Could not start upload: #{inspect(reason)}")}
    end
  end

  def handle_event("upload-complete", _params, socket) do
    {:noreply,
     socket
     |> assign(:video_upload_state, :processing)
     |> assign(:video_upload_message, "Upload complete. Mux is preparing protected playback…")
     |> push_event("mux-check-upload", %{})}
  end

  def handle_event(
        "check-upload",
        _params,
        %{assigns: %{video_upload: %{id: upload_id}}} = socket
      ) do
    case Media.upload_status(socket.assigns.current_user, upload_id) do
      {:ok, {:ready, playback_id, duration_seconds}} ->
        {:noreply,
         socket
         |> assign(:video_ready, %{
           video_provider: :mux,
           video_asset_id: playback_id,
           duration_seconds: duration_seconds
         })
         |> assign(:video_upload_state, :ready)
         |> assign(:video_upload_message, "Video is ready for protected playback.")}

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
         |> assign(:video_upload_message, "Mux could not process this upload: #{inspect(reason)}")}
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
    do: Map.take(resource, [:kind, :name, :storage_key, :url, :content_type, :byte_size])

  defp question_attrs(question), do: Map.take(question, [:question, :answer])

  defp resource_status(resource), do: Map.get(resource, :status, :ready)

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

  defp resource_key(resource, index), do: resource[:client_ref] || resource[:storage_key] || index

  defp replace_pending_resource(resources, client_ref, row) do
    Enum.map(resources, fn resource ->
      if resource[:client_ref] == client_ref, do: row, else: resource
    end)
  end

  defp mark_resource_error(resources, client_ref, message) do
    Enum.map(resources, fn resource ->
      if resource[:client_ref] == client_ref,
        do: Map.merge(resource, %{status: :error, error: message}),
        else: resource
    end)
  end

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

    missing_video =
      is_nil(video_ready) and
        (blank?(form[:video_asset_id].value) or blank?(form[:duration_seconds].value))

    Enum.any?(required, &blank?(form[&1].value)) or
      missing_video or
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

  defp string_to_kind("video"), do: :video
  defp string_to_kind("link"), do: :link
  defp string_to_kind(_), do: :document

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
