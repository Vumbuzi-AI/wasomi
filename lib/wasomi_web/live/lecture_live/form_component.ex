defmodule WasomiWeb.LectureLive.FormComponent do
  use WasomiWeb, :live_component

  alias Wasomi.{Catalog, Storage}

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
        <div class="grid gap-4 sm:grid-cols-2">
          <.input field={@form[:title]} type="text" label="Title" required />
          <.input field={@form[:position]} type="number" label="Position" min="1" required />
        </div>
        <.input field={@form[:description]} type="textarea" label="Description" rows="4" required />

        <section
          id="lecture-video"
          phx-hook="VideoPreview"
          class="space-y-4 rounded-2xl border border-black/5 bg-soft/40 p-4 sm:p-5"
        >
          <div>
            <h3 class="font-semibold text-dark">Lecture video</h3>
            <p class="mt-1 text-sm text-muted">
              The primary video remains used for learner playback.
            </p>
          </div>
          <video
            data-role="preview"
            controls
            class="hidden w-full rounded-xl border border-black/10 bg-black"
          >
          </video>
          <.input
            field={@form[:video_asset_id]}
            type="text"
            label="Video asset or playback ID"
            required
          />
          <label class="inline-flex cursor-pointer items-center gap-2 rounded-full bg-dark px-4 py-2.5 text-sm font-medium text-white transition hover:bg-primary">
            <.icon name="hero-arrow-up-tray" class="h-4 w-4" /> Choose primary video
            <.live_file_input upload={@uploads.video} class="sr-only" />
          </label>
          <p class="text-xs text-muted">MP4, MOV or WebM. The duration is detected automatically.</p>
          <div :for={entry <- @uploads.video.entries} class="space-y-1">
            <div class="h-2 overflow-hidden rounded-full bg-soft">
              <div class="h-full rounded-full bg-primary" style={"width: #{entry.progress}%"}></div>
            </div>
            <p :for={error <- upload_errors(@uploads.video, entry)} class="text-sm text-rose-600">
              {upload_error_to_string(error)}
            </p>
          </div>
          <div class="grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:video_provider]}
              type="select"
              label="Video provider"
              options={Ecto.Enum.values(Catalog.Lecture, :video_provider)}
              required
            />
            <.input
              field={@form[:duration_seconds]}
              type="number"
              label="Duration (seconds)"
              min="1"
              required
            />
          </div>
        </section>

        <section
          id="lecture-resources"
          phx-hook="R2ResourceUpload"
          data-target={@myself}
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
            <label class="inline-flex cursor-pointer items-center gap-2 rounded-xl border border-dashed border-primary bg-mint/40 px-4 py-3 text-sm font-medium text-primary transition hover:bg-mint">
              <.icon name="hero-plus-circle" class="h-5 w-5" /> Select one or more files
              <input
                data-role="file"
                type="file"
                multiple
                accept=".pdf,.doc,.docx,.ppt,.pptx,.txt,.mp4,.mov,.webm"
                class="sr-only"
              />
            </label>
            <p class="mt-2 text-xs text-muted">Documents up to 50 MB and videos up to 1 GB.</p>
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
          <.button
            disabled={save_disabled?(@form, @resource_rows, @question_rows, @uploads)}
            phx-disable-with="Saving..."
          >
            Save Lecture
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
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

    socket =
      if socket.assigns[:uploads] do
        socket
      else
        allow_upload(socket, :video,
          accept: ~w(.mp4 .mov .webm),
          max_entries: 1,
          max_file_size: 1_000_000_000
        )
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
    {:noreply, assign(socket, resource_rows: remove_at(socket.assigns.resource_rows, index))}
  end

  def handle_event("add-question", _params, socket) do
    {:noreply,
     assign(socket, question_rows: socket.assigns.question_rows ++ [%{question: "", answer: ""}])}
  end

  def handle_event("remove-question", %{"index" => index}, socket) do
    {:noreply, assign(socket, question_rows: remove_at(socket.assigns.question_rows, index))}
  end

  def handle_event("save", %{"lecture" => lecture_params} = params, socket) do
    lecture_params = put_uploaded_video(socket, lecture_params)
    questions = question_params(params, socket.assigns.question_rows)

    case validate_resources(socket.assigns.resource_rows) do
      :ok ->
        result =
          if socket.assigns.action == :new do
            lecture_params =
              Map.put(lecture_params, "module_id", socket.assigns.lecture.module_id)

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

  defp put_uploaded_video(socket, params) do
    case consume_uploaded_entries(socket, :video, fn %{path: tmp_path}, entry ->
           dir = Path.join(:code.priv_dir(:wasomi), "static/uploads/lectures")
           File.mkdir_p!(dir)
           filename = "#{entry.uuid}#{Path.extname(entry.client_name)}"
           File.cp!(tmp_path, Path.join(dir, filename))
           {:ok, "/uploads/lectures/#{filename}"}
         end) do
      [url | _] -> Map.merge(params, %{"video_asset_id" => url, "video_provider" => :mux})
      [] -> params
    end
  end

  defp resource_attrs(resource),
    do: Map.take(resource, [:kind, :name, :storage_key, :url, :content_type, :byte_size])

  defp question_attrs(question), do: Map.take(question, [:question, :answer])

  defp resource_status(resource), do: Map.get(resource, :status, :ready)

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

  defp save_disabled?(form, resources, questions, uploads) do
    required = [
      :title,
      :description,
      :video_provider,
      :video_asset_id,
      :duration_seconds,
      :position
    ]

    missing_video =
      blank?(form[:video_asset_id].value) and
        Map.get(uploads, :video, %{entries: []}).entries == []

    Enum.any?(required -- [:video_asset_id], &blank?(form[&1].value)) or
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

  defp upload_error_to_string(:too_large), do: "That video is larger than the 1 GB limit."
  defp upload_error_to_string(:not_accepted), do: "Please choose an MP4, MOV or WebM file."
  defp upload_error_to_string(_), do: "Could not accept that video."

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
