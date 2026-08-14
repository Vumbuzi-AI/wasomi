defmodule WasomiWeb.LectureLive.FormComponent do
  use WasomiWeb, :live_component

  require Logger

  alias Wasomi.{Catalog, Media, Storage}
  alias Wasomi.Catalog.Workers.{AttachLectureOverviewVideoWorker, GenerateLectureOverviewWorker}
  alias WasomiWeb.AdminLive.Components.ResourceUploader

  @impl true
  def render(assigns) do
    ~H"""
    <div id="lecture-form-component">
      <.header>
        {@title}
        <:subtitle :if={@action == :edit}>
          Add the lecture content, supporting resources, and common learner questions.
        </:subtitle>
        <:subtitle :if={@action == :new}>
          A few short steps — each one saves as you go, so nothing is lost if you close this
          partway through.
        </:subtitle>
      </.header>

      <%!-- Associated via the `form` attribute below rather than nested inside
      either .simple_form's or a wizard step's own <form> — nested <form>
      elements are invalid HTML and get silently dropped by the browser's
      parser on parse. Keeping this one as a real, separate <form> (rather
      than a plain div + phx-change-synced assign) means "Save link" always
      submits whatever is actually in the input at the moment of the click,
      with no server round-trip in between to go stale. --%>
      <form id="add-link-form" phx-submit="add-link" phx-target={@myself} class="hidden"></form>

      <div :if={@action == :new}>
        <.wizard_steps step={@step} max_reached_step={@max_reached_step} myself={@myself} />

        <.basics_step :if={@step == :basics} form={@form} myself={@myself} />

        <.video_step
          :if={@step == :video}
          myself={@myself}
          video_upload_state={@video_upload_state}
          video_thumbnail_url={@video_thumbnail_url}
          video_local_preview_url={@video_local_preview_url}
          video_filename={@video_filename}
          video_size={@video_size}
          video_upload_message={@video_upload_message}
        />

        <.resources_step
          :if={@step == :resources}
          myself={@myself}
          current_user={@current_user}
          uploads={@uploads}
          video_ready={@video_ready}
          resource_rows={@resource_rows}
          resource_error={@resource_error}
          resource_mode={@resource_mode}
          resource_link_reset={@resource_link_reset}
        />

        <.video_overview_step
          :if={@step == :video_overview}
          lecture={@lecture}
          myself={@myself}
          overview_generation={@overview_generation}
        />

        <.questions_step
          :if={@step == :questions}
          question_rows={@question_rows}
          myself={@myself}
          video_ready={@video_ready}
        />

        <.done_step
          :if={@step == :done}
          lecture={@lecture}
          myself={@myself}
          course_slug={@course_slug}
        />
      </div>

      <.simple_form
        :if={@action == :edit}
        for={@form}
        id="lecture-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Title" required />
        <.input field={@form[:description]} type="textarea" label="Description" rows="4" required />

        <.video_section
          myself={@myself}
          video_upload_state={@video_upload_state}
          video_thumbnail_url={@video_thumbnail_url}
          video_local_preview_url={@video_local_preview_url}
          video_filename={@video_filename}
          video_size={@video_size}
          video_upload_message={@video_upload_message}
        />

        <.resources_section
          myself={@myself}
          current_user={@current_user}
          uploads={@uploads}
          resource_rows={@resource_rows}
          resource_error={@resource_error}
          resource_mode={@resource_mode}
          resource_link_reset={@resource_link_reset}
        />

        <.overview_generation_section
          :if={@lecture.id}
          lecture={@lecture}
          overview_generation={@overview_generation}
          myself={@myself}
        />

        <.questions_section myself={@myself} question_rows={@question_rows} />

        <:actions>
          <p
            :if={save_disabled?(@form, @resource_rows, @question_rows, @video_ready)}
            class="text-sm text-amber-700"
          >
            Add a video or at least one resource, and finish all uploads, before saving.
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

  # --- Shared sections (reused by both the edit-mode single page and the
  # new-lecture wizard's Content/Questions steps) ---------------------------

  attr :myself, :any, required: true
  attr :video_upload_state, :atom, required: true
  attr :video_thumbnail_url, :any, default: nil
  attr :video_local_preview_url, :any, default: nil
  attr :video_filename, :any, default: nil
  attr :video_size, :any, default: nil
  attr :video_upload_message, :any, default: nil

  defp video_section(assigns) do
    ~H"""
    <section
      id="lecture-video"
      class="space-y-4 rounded-2xl border border-black/5 bg-soft/40 p-4 sm:p-5"
    >
      <div>
        <h3 class="font-semibold text-ink">Lecture video</h3>
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
          <p class="text-sm font-medium text-ink">Drop a video here, or click to choose one</p>
          <p class="text-xs text-muted">MP4, MOV or WebM</p>
        </div>

        <div :if={@video_upload_state != :idle} class="space-y-3">
          <button
            type="button"
            phx-click="remove-video"
            phx-target={@myself}
            aria-label="Remove selected video"
            class="pointer-events-auto absolute right-3 top-3 flex h-6 w-6 items-center justify-center rounded-full bg-ink text-white opacity-0 transition-[opacity,transform] duration-150 ease-out hover:bg-rose-600 group-hover:opacity-100 active:scale-[0.96]"
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
              <p class="truncate text-sm font-medium text-ink">{@video_filename}</p>
              <p class="text-xs text-muted">{format_file_size(@video_size)}</p>
            </div>
          </div>

          <div :if={@video_upload_state != :ready} class="h-2 overflow-hidden rounded-full bg-soft">
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
    """
  end

  attr :myself, :any, required: true
  attr :current_user, :map, required: true
  attr :uploads, :any, required: true
  attr :resource_rows, :list, required: true
  attr :resource_error, :any, default: nil
  attr :resource_mode, :atom, default: :upload
  attr :resource_link_reset, :integer, default: 0

  defp resources_section(assigns) do
    ~H"""
    <section
      id="lecture-resources"
      class="space-y-4 rounded-2xl border border-black/5 bg-white p-4 sm:p-5"
    >
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 class="font-semibold text-ink">Resources</h3>
          <p class="mt-1 text-sm text-muted">
            Add documents or useful links for learners.
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
                do: "bg-ink text-white",
                else: "text-muted hover:text-ink"
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
                do: "bg-ink text-white",
                else: "text-muted hover:text-ink"
              )
            ]}
          >
            Add link
          </button>
        </div>
      </div>
      <div data-role="resource-panel" data-mode="upload" class={@resource_mode != :upload && "hidden"}>
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
            class="w-full min-w-0 flex-1 rounded-xl border border-black/10 bg-white px-3 py-2.5 text-sm text-ink focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
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
        :if={@resource_rows == [] and @uploads.resources.entries == []}
        class="rounded-xl border border-dashed border-black/10 p-5 text-center text-sm text-muted"
      >
        No resources added yet.
      </div>
      <div
        :if={@resource_rows == [] and @uploads.resources.entries != []}
        class="rounded-xl border border-dashed border-black/10 p-5 text-center text-sm text-muted"
      >
        {pending_upload_message(@uploads.resources.entries)}
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
            <p class="truncate text-sm font-medium text-ink">{resource.name}</p>
            <p class="truncate text-xs text-muted">
              {resource.content_type || resource.url}
            </p>
            <div :if={resource_status(resource) == :uploading} class="mt-2 flex items-center gap-2">
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
    """
  end

  attr :lecture, :any, required: true
  attr :overview_generation, :any, default: nil
  attr :myself, :any, required: true

  defp overview_generation_section(assigns) do
    ~H"""
    <section
      id="lecture-overview-generation"
      class="space-y-4 rounded-2xl border border-black/5 bg-soft/40 p-4 sm:p-5"
    >
      <div>
        <h3 class="font-semibold text-ink">AI video overview</h3>
        <p class="mt-1 text-sm text-muted">
          Generates a narrated video from this lecture's resources — an alternative to uploading
          one directly.
        </p>
      </div>

      <p
        :if={overview_source_resources(@lecture) == []}
        class="rounded-xl bg-white px-4 py-3 text-sm text-muted"
      >
        Save this lecture with at least one document or link resource first.
      </p>

      <div :if={overview_source_resources(@lecture) != []}>
        <button
          :if={is_nil(@overview_generation) or @overview_generation.status in [:ready, :failed]}
          type="button"
          phx-click="generate-overview"
          phx-target={@myself}
          class="rounded-full border border-primary px-4 py-2 text-sm font-medium text-primary hover:bg-mint"
        >
          {if @overview_generation, do: "Generate again", else: "Generate video overview"}
        </button>

        <div
          :if={@overview_generation && @overview_generation.status in [:pending, :processing]}
          class="flex items-center gap-3 rounded-xl bg-white px-4 py-3"
        >
          <.icon name="hero-arrow-path" class="h-4 w-4 animate-spin text-primary" />
          <p class="text-sm text-ink">{generation_status_message(@overview_generation)}</p>
          <button
            type="button"
            phx-click="cancel-overview-generation"
            phx-target={@myself}
            class="ml-auto text-sm font-medium text-rose-600 hover:text-rose-800"
          >
            Cancel
          </button>
        </div>

        <p
          :if={@overview_generation && @overview_generation.status == :failed}
          class="mt-3 rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-700"
        >
          Generation failed: {@overview_generation.error_message || "unknown error"}
        </p>

        <% video_url = @overview_generation && overview_video_url(@overview_generation) %>

        <div :if={@overview_generation && @overview_generation.status == :ready} class="mt-3">
          <video :if={video_url} controls class="w-full max-w-md rounded-xl bg-black" src={video_url}>
          </video>
          <p :if={is_nil(video_url)} class="rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-700">
            Video generated, but no public URL is configured (R2_PUBLIC_URL) to preview it.
          </p>
        </div>

        <div :if={@overview_generation && @overview_generation.status == :ready} class="mt-4">
          <button
            :if={@overview_generation.attach_status in [:not_attached, :attach_failed]}
            type="button"
            phx-click="attach-overview-video"
            phx-target={@myself}
            class="rounded-full bg-ink px-4 py-2 text-sm font-medium text-white hover:bg-ink/90"
          >
            Use this as the lecture video
          </button>

          <div
            :if={@overview_generation.attach_status == :attaching}
            class="flex items-center gap-3 rounded-xl bg-white px-4 py-3"
          >
            <.icon name="hero-arrow-path" class="h-4 w-4 animate-spin text-primary" />
            <p class="text-sm text-ink">Attaching to the lecture… this can take a minute.</p>
            <button
              type="button"
              phx-click="refresh-overview-video-attach-status"
              phx-target={@myself}
              class="ml-auto text-sm font-medium text-primary hover:text-ink"
            >
              Refresh status
            </button>
          </div>

          <p
            :if={@overview_generation.attach_status == :attached}
            class="flex items-center gap-2 rounded-xl bg-mint px-4 py-3 text-sm font-medium text-primary"
          >
            <.icon name="hero-check-circle" class="h-4 w-4" /> This video is now the lecture's video.
          </p>

          <p
            :if={@overview_generation.attach_status == :attach_failed}
            class="mt-2 rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-700"
          >
            Couldn't attach this video: {@overview_generation.attach_error_message || "unknown error"}
          </p>
        </div>
      </div>
    </section>
    """
  end

  attr :myself, :any, required: true
  attr :question_rows, :list, required: true

  defp questions_section(assigns) do
    ~H"""
    <section class="space-y-4 rounded-2xl border border-black/5 bg-white p-4 sm:p-5">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 class="font-semibold text-ink">Common learner questions</h3>
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
          <p class="text-sm font-semibold text-ink">Question {index + 1}</p>
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
            class="w-full rounded-xl border border-black/10 bg-white px-3 py-2.5 text-sm text-ink focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
          />
          <textarea
            name={"questions[#{index}][answer]"}
            rows="3"
            placeholder="Write a clear answer..."
            required
            class="w-full rounded-xl border border-black/10 bg-white px-3 py-2.5 text-sm text-ink focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
          >{question.answer}</textarea>
        </div>
      </div>
    </section>
    """
  end

  # --- Wizard chrome and steps (new-lecture creation only) -----------------

  attr :step, :atom, required: true
  attr :max_reached_step, :integer, required: true
  attr :myself, :any, required: true

  defp wizard_steps(assigns) do
    ~H"""
    <div class="mb-6 flex items-center gap-2 rounded-full border border-black/10 bg-soft p-1.5">
      <button
        :for={
          {step, label} <- [
            {:basics, "Basics"},
            {:video, "Video"},
            {:resources, "Resources"},
            {:questions, "Questions"}
          ]
        }
        type="button"
        disabled={step_index(step) > @max_reached_step}
        phx-target={@myself}
        phx-click="go-to-step"
        phx-value-step={step}
        class={[
          "flex-1 rounded-full px-4 py-2 text-sm font-medium transition",
          @step == step && "bg-ink text-white",
          @step != step && step_index(step) <= @max_reached_step && "text-body hover:text-ink",
          step_index(step) > @max_reached_step && "cursor-not-allowed text-muted/50"
        ]}
      >
        {label}
      </button>
      <div class={[
        "flex-1 rounded-full px-4 py-2 text-center text-sm font-medium",
        @step == :done && "bg-ink text-white",
        @step != :done && "text-muted/50"
      ]}>
        Done
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :myself, :any, required: true

  defp basics_step(assigns) do
    ~H"""
    <div>
      <p class="mb-4 text-sm text-muted">
        Start with a title and description — you can add video, resources, and questions next.
      </p>
      <.simple_form
        for={@form}
        id="lecture-basics-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save-basics"
      >
        <.input field={@form[:title]} type="text" label="Title" required />
        <.input field={@form[:description]} type="textarea" label="Description" rows="4" required />

        <p :if={basics_disabled?(@form)} class="text-sm text-amber-700">
          Add a title and description to continue.
        </p>

        <:actions>
          <div class="ml-auto">
            <.button disabled={basics_disabled?(@form)} phx-disable-with="Saving...">
              Continue
            </.button>
          </div>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  attr :myself, :any, required: true
  attr :video_upload_state, :atom, required: true
  attr :video_thumbnail_url, :any, default: nil
  attr :video_local_preview_url, :any, default: nil
  attr :video_filename, :any, default: nil
  attr :video_size, :any, default: nil
  attr :video_upload_message, :any, default: nil

  defp video_step(assigns) do
    ~H"""
    <form id="lecture-video-form" phx-target={@myself} phx-submit="save-video">
      <p class="mb-4 text-sm text-muted">
        Optional — you can add resources instead on the next step.
      </p>

      <.video_section
        myself={@myself}
        video_upload_state={@video_upload_state}
        video_thumbnail_url={@video_thumbnail_url}
        video_local_preview_url={@video_local_preview_url}
        video_filename={@video_filename}
        video_size={@video_size}
        video_upload_message={@video_upload_message}
      />

      <div class="mt-6 flex items-center justify-between">
        <button
          type="button"
          phx-target={@myself}
          phx-click="go-to-step"
          phx-value-step="basics"
          class="text-sm font-medium text-muted hover:text-ink"
        >
          Back
        </button>
        <.button disabled={video_step_disabled?(@video_upload_state)} phx-disable-with="Saving...">
          Continue
        </.button>
      </div>
    </form>
    """
  end

  attr :myself, :any, required: true
  attr :current_user, :map, required: true
  attr :uploads, :any, required: true
  attr :video_ready, :any, default: nil
  attr :resource_rows, :list, required: true
  attr :resource_error, :any, default: nil
  attr :resource_mode, :atom, default: :upload
  attr :resource_link_reset, :integer, default: 0

  defp resources_step(assigns) do
    ~H"""
    <form
      id="lecture-resources-form"
      phx-target={@myself}
      phx-change="validate-resources"
      phx-submit="save-resources"
    >
      <p class="mb-4 text-sm text-muted">
        <%= if @video_ready do %>
          Optional — add supporting documents or links.
        <% else %>
          Add at least one document or link — no video was added.
        <% end %>
      </p>

      <.resources_section
        myself={@myself}
        current_user={@current_user}
        uploads={@uploads}
        resource_rows={@resource_rows}
        resource_error={@resource_error}
        resource_mode={@resource_mode}
        resource_link_reset={@resource_link_reset}
      />

      <div class="mt-6 flex items-center justify-between">
        <button
          type="button"
          phx-target={@myself}
          phx-click="go-to-step"
          phx-value-step="video"
          class="text-sm font-medium text-muted hover:text-ink"
        >
          Back
        </button>
        <.button
          disabled={content_disabled?(@resource_rows, @video_ready, @uploads.resources.entries)}
          phx-disable-with="Saving..."
        >
          Continue
        </.button>
      </div>
    </form>
    """
  end

  attr :lecture, :any, required: true
  attr :myself, :any, required: true
  attr :overview_generation, :any, default: nil

  defp video_overview_step(assigns) do
    ~H"""
    <div>
      <p class="mb-4 text-sm text-muted">
        Optional — generate a video from your resources, or skip and add one later.
      </p>

      <.overview_generation_section
        lecture={@lecture}
        overview_generation={@overview_generation}
        myself={@myself}
      />

      <div class="mt-6 flex items-center justify-between">
        <button
          type="button"
          phx-target={@myself}
          phx-click="go-to-step"
          phx-value-step="resources"
          class="text-sm font-medium text-muted hover:text-ink"
        >
          Back
        </button>
        <button
          type="button"
          phx-target={@myself}
          phx-click="continue-video-overview"
          class="rounded-full bg-ink px-5 py-2.5 text-sm font-medium text-white hover:bg-primary"
        >
          Continue
        </button>
      </div>
    </div>
    """
  end

  attr :question_rows, :list, required: true
  attr :myself, :any, required: true
  attr :video_ready, :any, default: nil

  defp questions_step(assigns) do
    ~H"""
    <form
      id="lecture-questions-form"
      phx-target={@myself}
      phx-change="validate-questions"
      phx-submit="save-questions"
    >
      <p class="mb-4 text-sm text-muted">
        Optional — you can add these later from the edit page.
      </p>

      <.questions_section myself={@myself} question_rows={@question_rows} />

      <div class="mt-6 flex items-center justify-between">
        <button
          type="button"
          phx-target={@myself}
          phx-click="go-to-step"
          phx-value-step={if is_nil(@video_ready), do: "video_overview", else: "resources"}
          class="text-sm font-medium text-muted hover:text-ink"
        >
          Back
        </button>
        <div class="flex items-center gap-3">
          <button
            type="button"
            phx-target={@myself}
            phx-click="skip-questions"
            class="text-sm font-medium text-muted hover:text-ink"
          >
            Skip for now
          </button>
          <.button disabled={questions_disabled?(@question_rows)} phx-disable-with="Saving...">
            Finish
          </.button>
        </div>
      </div>
    </form>
    """
  end

  attr :lecture, :any, required: true
  attr :myself, :any, required: true
  attr :course_slug, :string, required: true

  defp done_step(assigns) do
    ~H"""
    <div class="space-y-6 py-4 text-center">
      <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
        <.icon name="hero-check-circle" class="h-8 w-8" />
      </span>
      <div>
        <h3 class="text-lg font-semibold text-ink">"{@lecture.title}" is saved</h3>
        <p class="mt-1 text-sm text-muted">
          You can keep editing it any time from the course curriculum.
        </p>
      </div>
      <div class="flex items-center justify-center gap-3">
        <.link
          navigate={~p"/admin/courses/#{@course_slug}/lectures/#{@lecture.id}/quiz"}
          class="inline-flex items-center gap-1.5 rounded-full border border-primary px-5 py-2.5 text-sm font-medium text-primary hover:bg-mint"
        >
          <.icon name="hero-clipboard-document-check" class="h-4 w-4" /> Generate a quiz
        </.link>
        <button
          type="button"
          phx-target={@myself}
          phx-click="add-another-lecture"
          class="rounded-full border border-primary px-5 py-2.5 text-sm font-medium text-primary hover:bg-mint"
        >
          Add another lecture
        </button>
        <button
          type="button"
          phx-target={@myself}
          phx-click="finish"
          class="rounded-full bg-ink px-5 py-2.5 text-sm font-medium text-white hover:bg-primary"
        >
          Close
        </button>
      </div>
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

  # A targeted `send_update/3` from course_show.ex's `:lecture_overview_generation_updated`
  # handler (the PubSub broadcast lands on the shared LiveView process, not
  # this component — course_show.ex is the only place that can have a
  # `handle_info/2` for it, and routes the result back in here). Guarded on
  # matching `lecture_id` since course_show.ex broadcasts to this
  # component's id under both possible mount ids (the real lecture id in
  # edit mode, `:new_lecture` mid-wizard) without knowing which one is
  # actually live.
  @impl true
  def update(%{overview_generation: generation} = assigns, socket)
      when not is_map_key(assigns, :lecture) do
    if socket.assigns.lecture.id == generation.lecture_id do
      {:ok, socket |> assign(:overview_generation, generation) |> maybe_start_ticking()}
    else
      {:ok, socket}
    end
  end

  @impl true
  def update(%{lecture: lecture} = assigns, socket) do
    # `assign_new` for :lecture, deliberately — `update/2` runs again on
    # every re-render of the parent LiveView that this component is
    # mounted in (e.g. the curriculum-refreshing `:content_saved` message
    # this component itself sends after each wizard step), not just once
    # at mount. The parent's own `lecture` prop never changes mid-wizard
    # (course_show.ex sets it once, when "Add lecture" is clicked, and
    # never updates it again while the modal stays open), so blindly
    # re-assigning it here would stomp the *real*, persisted lecture this
    # component has since progressed to via save-basics/save-content back
    # to that original empty, unsaved struct.
    socket =
      socket
      |> assign(Map.delete(assigns, :lecture))
      |> assign_new(:lecture, fn ->
        if lecture.id,
          do: preload_content(lecture),
          else: %{lecture | resources: [], questions: []}
      end)

    lecture = socket.assigns.lecture
    existing_video_ready = existing_video_ready(lecture)

    socket =
      socket
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
      |> assign_new(:overview_generation, fn -> latest_overview_generation(lecture) end)
      |> assign_new(:overview_subscribed_lecture_id, fn -> nil end)
      |> assign_new(:step, fn -> :basics end)
      |> assign_new(:max_reached_step, fn -> 0 end)

    socket =
      if Map.has_key?(socket.assigns, :uploads) and
           Map.has_key?(socket.assigns.uploads, :resources) do
        socket
      else
        ResourceUploader.configure_upload(socket, lecture.id)
      end

    # Subscribe (once per distinct lecture id — "Add another lecture"
    # resets to a fresh, unsaved lecture mid-session, which later gets a
    # different real id once its own Basics step saves) so status updates
    # from the background generation job arrive live instead of only on a
    # manual "Refresh status" click. The resulting PubSub messages land on
    # this shared process's mailbox, but course_show.ex — not this
    # component — is what actually has a `handle_info/2` for them; see the
    # targeted `update/2` clause above for how they get routed back in.
    socket =
      if (connected?(socket) and lecture.id) &&
           socket.assigns.overview_subscribed_lecture_id != lecture.id do
        Catalog.subscribe_to_overview_generation(lecture)
        assign(socket, :overview_subscribed_lecture_id, lecture.id)
      else
        socket
      end

    {:ok, maybe_start_ticking(socket)}
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

  def handle_event("generate-overview", _params, socket) do
    lecture = socket.assigns.lecture

    case Catalog.create_overview_generation(lecture, socket.assigns.current_user) do
      {:ok, generation} ->
        Oban.insert(GenerateLectureOverviewWorker.new(%{"generation_id" => generation.id}))

        {:noreply, assign(socket, :overview_generation, generation)}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, "Could not start video overview generation. Try again.")}
    end
  end

  def handle_event("cancel-overview-generation", _params, socket) do
    case socket.assigns.overview_generation do
      %{status: status} = generation when status in [:pending, :processing] ->
        updated = Catalog.cancel_overview_generation(generation)
        {:noreply, assign(socket, :overview_generation, updated)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("attach-overview-video", _params, socket) do
    case socket.assigns.overview_generation do
      %{status: :ready} = generation ->
        updated = Catalog.mark_overview_video_attaching(generation)
        Oban.insert(AttachLectureOverviewVideoWorker.new(%{"generation_id" => updated.id}))

        {:noreply, assign(socket, :overview_generation, updated)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("refresh-overview-video-attach-status", _params, socket) do
    case socket.assigns.overview_generation do
      nil ->
        {:noreply, socket}

      generation ->
        {:noreply,
         assign(socket, :overview_generation, Catalog.get_overview_generation!(generation.id))}
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
          Catalog.update_lecture_content(
            socket.assigns.lecture,
            lecture_params,
            socket.assigns.resource_rows,
            questions
          )

        case result do
          {:ok, lecture} ->
            notify_parent({:saved, lecture})

            {:noreply,
             socket
             |> put_flash(:info, "Lecture updated successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, form: to_form(changeset, action: :validate))}

          {:error, :video_or_resource_required} ->
            {:noreply,
             assign(socket,
               resource_error:
                 "Add a video, or at least one resource (document, link, etc.), before saving."
             )}

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

  def handle_event("save-basics", %{"lecture" => lecture_params}, socket) do
    lecture = socket.assigns.lecture

    result =
      if is_nil(lecture.id) do
        lecture_params
        |> Map.put("module_id", lecture.module_id)
        |> Map.put("position", lecture.position)
        |> Catalog.create_lecture()
      else
        Catalog.update_lecture(lecture, lecture_params)
      end

    case result do
      {:ok, saved_lecture} ->
        saved_lecture = %{
          saved_lecture
          | resources: lecture.resources,
            questions: lecture.questions
        }

        notify_parent({:content_saved, saved_lecture})

        {:noreply,
         socket
         |> assign(:lecture, saved_lecture)
         |> assign(:form, to_form(Catalog.change_lecture(saved_lecture)))
         |> advance_to(:video)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  def handle_event("save-video", _params, socket) do
    case socket.assigns.video_ready do
      nil ->
        {:noreply, advance_to(socket, :resources)}

      _video_ready ->
        lecture_params = put_video_fields(socket, %{})

        case Catalog.update_lecture_content(
               socket.assigns.lecture,
               lecture_params,
               socket.assigns.resource_rows,
               socket.assigns.question_rows
             ) do
          {:ok, lecture} ->
            notify_parent({:content_saved, lecture})
            {:noreply, socket |> assign(:lecture, lecture) |> advance_to(:resources)}

          {:error, _reason} ->
            {:noreply,
             assign(socket, resource_error: "Could not save this lecture's video. Try again.")}
        end
    end
  end

  # The Resources step's form has no changeset-backed fields of its own —
  # this exists only because `live_file_input`/`allow_upload` requires the
  # enclosing form to have a `phx-change` binding (in addition to
  # `phx-submit`) to track upload progress at all. Without it, file
  # selection silently does nothing: no error, no progress, no entry.
  def handle_event("validate-resources", _params, socket), do: {:noreply, socket}

  def handle_event("save-resources", params, socket) do
    socket = consume_resource_uploads(socket)
    lecture_params = put_video_fields(socket, Map.get(params, "lecture", %{}))

    case validate_resources(socket.assigns.resource_rows) do
      :ok ->
        case Catalog.update_lecture_content(
               socket.assigns.lecture,
               lecture_params,
               socket.assigns.resource_rows,
               socket.assigns.question_rows
             ) do
          {:ok, lecture} ->
            notify_parent({:content_saved, lecture})

            next_step =
              if is_nil(socket.assigns.video_ready), do: :video_overview, else: :questions

            {:noreply, socket |> assign(:lecture, lecture) |> advance_to(next_step)}

          {:error, :video_or_resource_required} ->
            {:noreply,
             assign(socket,
               resource_error:
                 "Add a video, or at least one resource (document, link, etc.), before continuing."
             )}

          {:error, _reason} ->
            {:noreply,
             assign(socket,
               resource_error:
                 "Could not save this lecture's content. Check the highlighted fields."
             )}
        end

      {:error, message} ->
        {:noreply, assign(socket, resource_error: message)}
    end
  end

  def handle_event("continue-video-overview", _params, socket) do
    {:noreply, advance_to(socket, :questions)}
  end

  # Keeps `@question_rows` in sync with what's actually typed, as it's
  # typed — without this, `questions_disabled?/1` (gating the Finish
  # button) only ever sees the blank row `add-question` created, since
  # nothing else updates the server's copy of the text as the admin fills
  # it in. Deliberately doesn't drop blank rows the way `save-questions`'s
  # final normalization does — a row disappearing the instant it's added
  # (before anything's been typed into it) would be its own bug.
  def handle_event("validate-questions", %{"questions" => questions}, socket) do
    rows =
      questions
      |> Enum.sort_by(fn {index, _} -> parse_integer(index) end)
      |> Enum.map(fn {_index, attrs} -> normalize_question(attrs) end)

    {:noreply, assign(socket, :question_rows, rows)}
  end

  def handle_event("validate-questions", _params, socket), do: {:noreply, socket}

  def handle_event("save-questions", params, socket) do
    questions = question_params(params, socket.assigns.question_rows)

    case Catalog.update_lecture_content(
           socket.assigns.lecture,
           %{},
           socket.assigns.resource_rows,
           questions
         ) do
      {:ok, lecture} ->
        notify_parent({:content_saved, lecture})

        {:noreply,
         socket
         |> assign(lecture: lecture, question_rows: questions)
         |> advance_to(:done)}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           resource_error: "Could not save these questions. Check the highlighted fields."
         )}
    end
  end

  def handle_event("skip-questions", _params, socket) do
    {:noreply, advance_to(socket, :done)}
  end

  def handle_event("go-to-step", %{"step" => step}, socket) do
    case step_from_param(step) do
      {:ok, step_atom} ->
        if step_index(step_atom) <= socket.assigns.max_reached_step do
          {:noreply, assign(socket, :step, step_atom)}
        else
          {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("finish", _params, socket) do
    notify_parent({:saved, socket.assigns.lecture})
    {:noreply, push_patch(socket, to: socket.assigns.patch)}
  end

  def handle_event("add-another-lecture", _params, socket) do
    lecture = socket.assigns.lecture

    fresh_lecture = %Catalog.Lecture{
      module_id: lecture.module_id,
      position: lecture.position + 1,
      resources: [],
      questions: []
    }

    {:noreply,
     socket
     |> assign(:lecture, fresh_lecture)
     |> assign(:form, to_form(Catalog.change_lecture(fresh_lecture)))
     |> assign(:step, :basics)
     |> assign(:max_reached_step, 0)
     |> assign(:resource_rows, [])
     |> assign(:question_rows, [])
     |> assign(:resource_error, nil)
     |> assign(:resource_mode, :upload)
     |> assign(:resource_link_reset, 0)
     |> assign(:video_upload, nil)
     |> assign(:video_upload_state, :idle)
     |> assign(:video_upload_message, nil)
     |> assign(:video_ready, nil)
     |> assign(:video_thumbnail_url, nil)
     |> assign(:video_local_preview_url, nil)
     |> assign(:video_filename, nil)
     |> assign(:video_size, nil)
     |> assign(:overview_generation, nil)
     |> push_event("mux-reset", %{})}
  end

  defp advance_to(socket, step) do
    socket
    |> assign(:step, step)
    |> assign(:max_reached_step, max(socket.assigns.max_reached_step, step_index(step)))
  end

  defp step_index(:basics), do: 0
  defp step_index(:video), do: 1
  defp step_index(:resources), do: 2
  defp step_index(:video_overview), do: 3
  defp step_index(:questions), do: 4
  defp step_index(:done), do: 5

  defp step_from_param("basics"), do: {:ok, :basics}
  defp step_from_param("video"), do: {:ok, :video}
  defp step_from_param("resources"), do: {:ok, :resources}
  defp step_from_param("video_overview"), do: {:ok, :video_overview}
  defp step_from_param("questions"), do: {:ok, :questions}
  defp step_from_param(_step), do: :error

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

  # `nil` for an unsaved (:new-action) lecture — generation needs a
  # persisted lecture id, and its resources need to already be saved (the
  # worker reads them from the DB, not from this form's live draft state).
  defp latest_overview_generation(%Catalog.Lecture{id: id}) when not is_nil(id) do
    %Catalog.Lecture{id: id}
    |> Catalog.list_overview_generations_for_lecture()
    |> List.first()
  end

  defp latest_overview_generation(_lecture), do: nil

  # Checked against `lecture.resources` (persisted, from the DB) rather
  # than `@resource_rows` (this form's live draft state) deliberately —
  # the worker reads a fresh DB preload, so a resource only just added in
  # this form (not yet saved) wouldn't be visible to it either.
  defp overview_source_resources(%Catalog.Lecture{resources: resources})
       when is_list(resources) do
    Enum.filter(resources, &(&1.kind in [:document, :link]))
  end

  defp overview_source_resources(_lecture), do: []

  defp overview_video_url(generation), do: Catalog.overview_video_url(generation)

  # Progressively discloses more detail rather than dumping elapsed time
  # and a "may be stuck" caveat on the user from the very first second —
  # showing "running for 0s" the instant this starts reads as broken, not
  # reassuring, and warning language has no business appearing before
  # it's actually earned. `course_show.ex`'s `:tick_overview_generation`
  # handler re-renders this every second (see `maybe_start_ticking/1`
  # below) so the elapsed time genuinely counts up live.
  @generation_elapsed_grace_seconds 10
  # A real, empirically observed 10-scene generation took 6m13s (measured
  # directly from a generation's inserted_at -> updated_at once :ready) —
  # this is a multi-step AI video pipeline (script -> narration -> image
  # generation -> rendering per scene), not a quick text call, and a
  # longer lecture's source material can easily produce close to the max
  # scene count. The threshold needs real headroom above that observed
  # normal case, not a guessed "a minute or two."
  @generation_stuck_threshold_seconds 600

  defp generation_status_message(%{inserted_at: inserted_at}) do
    seconds = DateTime.diff(DateTime.utc_now(), inserted_at)

    cond do
      seconds < @generation_elapsed_grace_seconds ->
        "Generating…"

      seconds < @generation_stuck_threshold_seconds ->
        "Generating… running for #{format_duration(seconds)}. Can take several minutes — " <>
          "longer lectures with more resources take longer."

      true ->
        "Generating… running for #{format_duration(seconds)}. This is taking longer than " <>
          "usual — it may be stuck."
    end
  end

  defp format_duration(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3600)}h #{rem(div(seconds, 60), 60)}m"
    end
  end

  # A LiveComponent has no process of its own to `Process.send_after/3`
  # from (`self()` here resolves to the *parent* LiveView), so the actual
  # repeating timer lives in course_show.ex's `:tick_overview_generation`
  # handler, kicked off once here and then perpetuating itself for as
  # long as the generation stays `:pending`/`:processing` — see that
  # handler for where it stops. Guarded on `overview_ticking_generation_id`
  # so a re-render (this runs on every `update/2`) never starts a second,
  # competing tick loop for the same generation.
  defp maybe_start_ticking(socket) do
    ticking_id = socket.assigns[:overview_ticking_generation_id]

    case socket.assigns[:overview_generation] do
      %{id: id, status: status} when status in [:pending, :processing] and ticking_id != id ->
        if connected?(socket) do
          Process.send_after(self(), {:tick_overview_generation, id}, 1000)
        end

        assign(socket, :overview_ticking_generation_id, id)

      _ ->
        socket
    end
  end

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
    case socket.assigns.video_ready do
      %{video_asset_id: asset_id, duration_seconds: duration} ->
        Map.merge(params, %{
          "video_provider" => "mux",
          "video_asset_id" => asset_id,
          "duration_seconds" => duration
        })

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

  # `@uploads.resources.entries` (raw, in-flight/finished upload entries)
  # and `@resource_rows` (committed resources) are two different lists —
  # an entry reaching 100% doesn't move it into `resource_rows` until the
  # form is actually submitted (`consume_resource_uploads/1`). Without
  # this, the empty state below reads "No resources added yet" even while
  # fully-uploaded files are sitting right above it, which looks broken.
  defp pending_upload_message(entries) do
    count = length(entries)
    noun = if count == 1, do: "file", else: "files"

    if Enum.all?(entries, &(&1.progress == 100)) do
      "#{count} #{noun} uploaded — save to attach #{if count == 1, do: "it", else: "them"}."
    else
      "Uploading #{count} #{noun}…"
    end
  end

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
      (is_nil(video_ready) and resources == []) or
      Enum.any?(resources, &(resource_status(&1) in [:uploading, :error])) or
      Enum.any?(resources, &(blank?(&1[:name]) or (&1[:kind] == :link and !valid_url?(&1[:url])))) or
      Enum.any?(questions, &(blank?(&1[:question]) or blank?(&1[:answer])))
  end

  defp basics_disabled?(form) do
    Enum.any?([:title, :description], &blank?(form[&1].value))
  end

  # Video is always optional (Resources can satisfy the requirement on its
  # own), so this only ever blocks leaving mid-upload — never on a genuinely
  # empty/skipped video.
  defp video_step_disabled?(video_upload_state) do
    video_upload_state in [:uploading, :processing]
  end

  # `resources` is `@resource_rows` — the *committed* resource list, which
  # only fills in once the form is actually submitted
  # (`consume_resource_uploads/1`). `upload_entries` is the raw, in-flight
  # `@uploads.resources.entries` list, which can hold fully-uploaded files
  # `resources` doesn't know about yet — without counting those too, this
  # would stay disabled forever once files finish uploading, since nothing
  # ever moves them into `resources` before Continue is clicked.
  defp content_disabled?(resources, video_ready, upload_entries) do
    has_resources? = resources != [] or Enum.any?(upload_entries, &(&1.progress == 100))

    (is_nil(video_ready) and not has_resources?) or
      Enum.any?(upload_entries, &(&1.progress < 100)) or
      Enum.any?(resources, &(resource_status(&1) in [:uploading, :error])) or
      Enum.any?(resources, &(blank?(&1[:name]) or (&1[:kind] == :link and !valid_url?(&1[:url]))))
  end

  defp questions_disabled?(questions) do
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
