defmodule WasomiWeb.AdminLive.QuizEdit do
  use WasomiWeb, :live_view

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Question
  alias Wasomi.Assessments.QuizGeneration
  alias Wasomi.Assessments.Workers.GenerateQuizFromPDFWorker
  alias Wasomi.Catalog

  @max_pdf_bytes 25_000_000

  @impl true
  def mount(%{"course_slug" => course_slug, "id" => quiz_id}, _session, socket) do
    quiz = load_quiz!(quiz_id, course_slug)

    if connected?(socket), do: Assessments.subscribe_to_generation(quiz)

    {:ok,
     socket
     |> assign(:page_title, "Edit quiz")
     |> assign(:course_slug, course_slug)
     |> assign(:publish_errors, [])
     |> assign(:new_question_form, nil)
     |> assign(:new_question_type, nil)
     |> assign(:editing_title?, false)
     |> assign(:quiz_form, to_form(Assessments.change_quiz(quiz)))
     |> assign(:generations, Assessments.list_generations_for_quiz(quiz))
     |> assign(:discarding_generation_id, nil)
     |> assign(:confirming_delete_all?, false)
     |> assign(:confirming_publish_all?, false)
     |> assign(:deleting_question_id, nil)
     |> allow_upload(:source_pdf,
       accept: ~w(.pdf),
       max_entries: 1,
       max_file_size: @max_pdf_bytes,
       auto_upload: true
     )
     |> assign_quiz(quiz)}
  end

  @impl true
  def handle_info({:quiz_generation_updated, _generation}, socket) do
    {:noreply,
     socket
     |> assign(:generations, Assessments.list_generations_for_quiz(socket.assigns.quiz))
     |> reload_quiz()}
  end

  @impl true
  def handle_event("validate_question", %{"id" => id, "question" => params} = full, socket) do
    question = find_question!(socket.assigns.quiz, id)
    params = apply_correct_option(params, correct_option_id(full, "question-#{id}"))

    changeset =
      question
      |> Assessments.change_question(params)
      |> Map.put(:action, :validate)

    forms = Map.put(socket.assigns.question_forms, question.id, to_form(changeset))

    {:noreply,
     socket
     |> assign(:question_forms, forms)
     |> mark_dirty(question.id)}
  end

  def handle_event("validate_new_question", %{"question" => params} = full, socket) do
    params = apply_correct_option(params, correct_option_id(full, "new-question"))

    changeset =
      %Question{quiz_id: socket.assigns.quiz.id}
      |> Assessments.change_question(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :new_question_form, to_form(changeset))}
  end

  def handle_event("add_option", %{"id" => "new"}, socket) do
    changeset = socket.assigns.new_question_form.source
    options = get_active_options(changeset)

    if length(options) < 4 do
      new_position = length(options) + 1

      new_option = %Wasomi.Assessments.QuestionOption{
        label: "",
        correct: false,
        position: new_position
      }

      updated_options = options ++ [new_option]

      updated_changeset = Ecto.Changeset.put_assoc(changeset, :question_options, updated_options)
      {:noreply, assign(socket, :new_question_form, to_form(updated_changeset))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_option", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    form = Map.fetch!(socket.assigns.question_forms, id)
    changeset = form.source
    options = get_active_options(changeset)

    if length(options) < 4 do
      new_position = length(options) + 1

      new_option = %Wasomi.Assessments.QuestionOption{
        label: "",
        correct: false,
        position: new_position
      }

      updated_options = options ++ [new_option]

      updated_changeset = Ecto.Changeset.put_assoc(changeset, :question_options, updated_options)
      forms = Map.put(socket.assigns.question_forms, id, to_form(updated_changeset))

      {:noreply,
       socket
       |> assign(:question_forms, forms)
       |> mark_dirty(id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_option", %{"id" => "new", "index" => index_str}, socket) do
    index = String.to_integer(index_str)
    changeset = socket.assigns.new_question_form.source
    options = get_active_options(changeset)

    if length(options) > 2 do
      updated_options = List.delete_at(options, index)
      updated_options = reindex_positions(updated_options)

      updated_changeset = Ecto.Changeset.put_assoc(changeset, :question_options, updated_options)
      {:noreply, assign(socket, :new_question_form, to_form(updated_changeset))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_option", %{"id" => id_str, "index" => index_str}, socket) do
    id = String.to_integer(id_str)
    index = String.to_integer(index_str)
    form = Map.fetch!(socket.assigns.question_forms, id)
    changeset = form.source
    options = get_active_options(changeset)

    if length(options) > 2 do
      updated_options = List.delete_at(options, index)
      updated_options = reindex_positions(updated_options)

      updated_changeset = Ecto.Changeset.put_assoc(changeset, :question_options, updated_options)
      forms = Map.put(socket.assigns.question_forms, id, to_form(updated_changeset))

      {:noreply,
       socket
       |> assign(:question_forms, forms)
       |> mark_dirty(id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_question", %{"id" => id, "question" => params} = full, socket) do
    question = find_question!(socket.assigns.quiz, id)
    params = apply_correct_option(params, correct_option_id(full, "question-#{id}"))

    case Assessments.update_question(question, params) do
      {:ok, _question} ->
        {:noreply,
         socket
         |> put_flash(:info, "Question saved.")
         |> assign(:publish_errors, [])
         |> reload_quiz()}

      {:error, changeset} ->
        forms =
          Map.put(socket.assigns.question_forms, question.id, to_form(changeset, action: :insert))

        {:noreply,
         socket
         |> assign(:question_forms, forms)
         |> mark_dirty(question.id)}
    end
  end

  def handle_event("publish_question", %{"id" => id}, socket) do
    question = find_question!(socket.assigns.quiz, id)
    {:ok, _published} = Assessments.publish_question(question)

    {:noreply,
     socket
     |> put_flash(:info, "Question published.")
     |> reload_quiz()}
  end

  def handle_event("new_question", params, socket) do
    type = Map.get(params, "type", "multiple_choice")

    changeset =
      Assessments.change_question(%Question{quiz_id: socket.assigns.quiz.id}, %{
        position: next_position(socket.assigns.quiz),
        status: :draft,
        question_options: blank_options(type)
      })

    {:noreply,
     socket
     |> assign(:new_question_form, to_form(changeset))
     |> assign(:new_question_type, type)}
  end

  def handle_event("cancel_new_question", _params, socket) do
    {:noreply,
     socket
     |> assign(:new_question_form, nil)
     |> assign(:new_question_type, nil)}
  end

  def handle_event("save_new_question", %{"question" => params} = full, socket) do
    params =
      params
      |> apply_correct_option(correct_option_id(full, "new-question"))
      |> Map.put("position", to_string(next_position(socket.assigns.quiz)))
      |> Map.put("status", "draft")

    case Assessments.create_question(socket.assigns.quiz, params) do
      {:ok, _question} ->
        {:noreply,
         socket
         |> put_flash(:info, "Question added.")
         |> assign(:new_question_form, nil)
         |> assign(:new_question_type, nil)
         |> assign(:publish_errors, [])
         |> reload_quiz()}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_question_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("confirm_delete_question", %{"id" => id}, socket) do
    {:noreply, assign(socket, :deleting_question_id, id)}
  end

  def handle_event("cancel_delete_question", _params, socket) do
    {:noreply, assign(socket, :deleting_question_id, nil)}
  end

  def handle_event("delete_question", %{"id" => id}, socket) do
    question = find_question!(socket.assigns.quiz, id)
    {:ok, _question} = Assessments.delete_question(question)

    {:noreply,
     socket
     |> put_flash(:info, "Question removed.")
     |> assign(:publish_errors, [])
     |> assign(:deleting_question_id, nil)
     |> reload_quiz()}
  end

  def handle_event("reorder_questions", %{"ids" => ids}, socket) do
    case Assessments.reorder_questions(socket.assigns.quiz, ids) do
      {:ok, _result} ->
        {:noreply, reload_quiz(socket)}

      {:error, :invalid_order} ->
        {:noreply,
         put_flash(socket, :error, "Questions could not be reordered. Refresh and try again.")}
    end
  end

  def handle_event("publish", _params, socket) do
    case Assessments.publish_quiz(socket.assigns.quiz) do
      {:ok, quiz} ->
        {:noreply,
         socket
         |> put_flash(:info, "Quiz published and is now active for enrolled learners.")
         |> assign(:publish_errors, [])
         |> assign_quiz(quiz)}

      {:error, {:incomplete_quiz, errors}} ->
        {:noreply, assign(socket, :publish_errors, errors)}
    end
  end

  def handle_event("start_editing_title", _params, socket) do
    {:noreply, assign(socket, :editing_title?, true)}
  end

  def handle_event("cancel_editing_title", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_title?, false)
     |> assign(:quiz_form, to_form(Assessments.change_quiz(socket.assigns.quiz)))}
  end

  def handle_event("update_quiz_settings", %{"quiz" => params}, socket) do
    case Assessments.update_quiz(socket.assigns.quiz, params) do
      {:ok, quiz} ->
        {:noreply,
         socket
         |> put_flash(:info, "Quiz settings updated.")
         |> assign(:quiz, quiz)
         |> assign(:quiz_form, to_form(Assessments.change_quiz(quiz)))
         |> assign(:editing_title?, false)}

      {:error, changeset} ->
        {:noreply, assign(socket, :quiz_form, to_form(changeset))}
    end
  end

  def handle_event("validate", params, socket) do
    resource_keys = params |> Map.get("resources", []) |> List.wrap()
    {:noreply, assign(socket, :selected_resources, resource_keys)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :source_pdf, ref)}
  end

  def handle_event("generate", params, socket) do
    quiz = socket.assigns.quiz
    user = socket.assigns.current_user

    if socket.assigns.module_ready? do
      resource_keys = params |> Map.get("resources", []) |> List.wrap()

      pdf_results =
        consume_uploaded_entries(socket, :source_pdf, fn %{path: path}, entry ->
          {:ok, start_generation(quiz, user, entry.client_name, path)}
        end)

      cond do
        pdf_results != [] ->
          case pdf_results do
            [%QuizGeneration{}] ->
              {:noreply,
               socket
               |> put_flash(:info, "PDF uploaded. Generating draft questions in the background…")
               |> assign(:generations, Assessments.list_generations_for_quiz(quiz))}

            [{:error, reason}] ->
              {:noreply,
               put_flash(socket, :error, "Could not start generation: #{inspect(reason)}")}
          end

        resource_keys != [] ->
          label = source_label(resource_keys, socket.assigns)
          {:ok, generation} = Assessments.create_generation(quiz, user, label)

          %{"generation_id" => generation.id, "resource_selection" => resource_keys}
          |> GenerateQuizFromPDFWorker.new()
          |> Oban.insert()

          {:noreply,
           socket
           |> put_flash(:info, "Generating draft questions from selected module resources…")
           |> assign(:generations, Assessments.list_generations_for_quiz(quiz))}

        true ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Select at least one module resource or upload a PDF document."
           )}
      end
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "Every lecture in this module must have a generated lecture quiz before generating the module quiz."
       )}
    end
  end

  def handle_event("confirm_discard_generation", %{"id" => id}, socket) do
    {:noreply, assign(socket, :discarding_generation_id, String.to_integer(id))}
  end

  def handle_event("cancel_discard_generation", _params, socket) do
    {:noreply, assign(socket, :discarding_generation_id, nil)}
  end

  def handle_event("discard_generation_drafts", %{"id" => id}, socket) do
    generation = Assessments.get_generation!(id)
    {count, _} = Assessments.discard_generation_drafts(generation)

    {:noreply,
     socket
     |> put_flash(:info, "Discarded #{count} draft question(s) from this batch.")
     |> assign(:discarding_generation_id, nil)
     |> reload_quiz()}
  end

  def handle_event("confirm_delete_all_drafts", _params, socket) do
    {:noreply, assign(socket, :confirming_delete_all?, true)}
  end

  def handle_event("cancel_delete_all_drafts", _params, socket) do
    {:noreply, assign(socket, :confirming_delete_all?, false)}
  end

  def handle_event("delete_all_drafts", _params, socket) do
    quiz = socket.assigns.quiz
    {count, _} = Assessments.discard_all_drafts(quiz)

    {:noreply,
     socket
     |> put_flash(:info, "Deleted #{count} draft question(s).")
     |> assign(:confirming_delete_all?, false)
     |> reload_quiz()}
  end

  def handle_event("confirm_publish_all_drafts", _params, socket) do
    {:noreply, assign(socket, :confirming_publish_all?, true)}
  end

  def handle_event("cancel_publish_all_drafts", _params, socket) do
    {:noreply, assign(socket, :confirming_publish_all?, false)}
  end

  def handle_event("publish_all_drafts", _params, socket) do
    quiz = socket.assigns.quiz
    {count, _} = Assessments.publish_all_drafts(quiz)

    {:noreply,
     socket
     |> put_flash(:info, "Published #{count} question(s).")
     |> assign(:confirming_publish_all?, false)
     |> reload_quiz()}
  end

  defp reindex_positions(options) do
    options
    |> Enum.with_index(1)
    |> Enum.map(fn {opt, pos} ->
      case opt do
        %Ecto.Changeset{} = cs -> Ecto.Changeset.put_change(cs, :position, pos)
        struct -> %{struct | position: pos}
      end
    end)
  end

  defp get_active_options(changeset) do
    Ecto.Changeset.get_assoc(changeset, :question_options)
    |> Enum.reject(fn
      %Ecto.Changeset{action: action} -> action in [:replace, :delete]
      _ -> false
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:courses} current_user={@current_user}>
      <div class="mx-auto max-w-4xl space-y-8 px-5 py-10 lg:px-8">
        <div class="flex flex-wrap items-center justify-between gap-4">
          <.link
            navigate={~p"/admin/courses/#{@course_slug}"}
            class="inline-flex items-center gap-1.5 text-sm font-medium text-muted hover:text-primary transition active:scale-[0.96]"
          >
            <.icon name="hero-arrow-left-mini" class="h-4 w-4" /> Back to course
          </.link>
        </div>

        <header>
          <p class="text-sm font-semibold uppercase tracking-wider text-primary">Quiz editor</p>

          <div :if={!@editing_title?} class="mt-2 flex items-center gap-2">
            <h1 id="quiz-title" class="text-3xl font-semibold text-ink">{@quiz.title}</h1>
            <button
              type="button"
              id="edit-title"
              phx-click="start_editing_title"
              aria-label="Rename quiz"
              class="rounded-lg p-1.5 text-muted hover:bg-surface hover:text-primary transition active:scale-[0.96]"
            >
              <.icon name="hero-pencil-square" class="h-5 w-5" />
            </button>
          </div>

          <.form
            :if={@editing_title?}
            for={@quiz_form}
            id="quiz-title-form"
            phx-submit="update_quiz_settings"
            class="mt-2 flex flex-wrap items-start gap-3"
          >
            <div>
              <input
                type="text"
                name={@quiz_form[:title].name}
                id={@quiz_form[:title].id}
                value={@quiz_form[:title].value}
                autofocus
                class="w-80 max-w-full rounded-lg border border-black/10 px-3 py-2 text-lg font-semibold text-ink focus:border-primary focus:ring-0"
              />
              <.field_error field={@quiz_form[:title]} />
            </div>
            <button
              type="submit"
              class="rounded-full bg-ink px-4 py-2 text-sm font-semibold text-white hover:bg-primary transition active:scale-[0.96]"
            >
              Save
            </button>
            <button
              type="button"
              phx-click="cancel_editing_title"
              class="text-sm font-medium text-muted hover:text-ink transition active:scale-[0.96]"
            >
              Cancel
            </button>
          </.form>

          <p class="mt-2 text-body">
            Edit questions inline and drag to reorder. Published questions are live immediately for learners.
          </p>
        </header>

        <div
          :if={@publish_errors != []}
          id="publish-errors"
          role="alert"
          class="rounded-2xl border border-red-200 bg-red-50 p-5 text-sm text-red-700"
        >
          <p class="font-semibold">The quiz is not ready to publish:</p>
          <ul class="mt-2 list-disc space-y-1 pl-5">
            <li :for={error <- @publish_errors}>{error}</li>
          </ul>
        </div>

        <section class="rounded-3xl border border-black/5 bg-white p-6 shadow-card">
          <.form
            for={@quiz_form}
            id="quiz-settings-form"
            phx-submit="update_quiz_settings"
            class="flex flex-wrap items-center gap-4"
          >
            <label for={@quiz_form[:passing_score_percent].id} class="text-lg font-semibold text-ink">
              Passing score
            </label>
            <div class="flex items-center gap-2">
              <input
                type="number"
                name={@quiz_form[:passing_score_percent].name}
                id={@quiz_form[:passing_score_percent].id}
                value={@quiz_form[:passing_score_percent].value}
                min="0"
                max="100"
                class="w-24 rounded-lg border border-black/10 px-3 py-2 text-sm text-ink focus:border-primary focus:ring-0"
              />
              <span class="text-sm text-body">%</span>
            </div>
            <button
              type="submit"
              class="rounded-full bg-ink px-5 py-2 text-sm font-medium text-white transition hover:bg-primary"
            >
              Save
            </button>
            <.field_error field={@quiz_form[:passing_score_percent]} />
          </.form>
        </section>

        <details
          id="generation-section"
          open={@generations != [] or @quiz.questions == []}
          class="group rounded-3xl border border-black/5 bg-white p-6 shadow-card"
        >
          <summary class="flex cursor-pointer list-none items-center justify-between gap-3 [&::-webkit-details-marker]:hidden">
            <h2 class="text-lg font-semibold text-ink">AI generation &amp; settings</h2>
            <.icon
              name="hero-chevron-down"
              class="h-4 w-4 shrink-0 text-muted transition group-open:rotate-180"
            />
          </summary>

          <div class="mt-5 space-y-5">
            <div
              :if={!@module_ready?}
              class="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800"
            >
              <p class="font-semibold flex items-center gap-2 text-amber-900">
                <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-amber-600" />
                Module Quiz Generation Locked
              </p>
              <p class="mt-1 text-xs text-amber-800">
                Every lecture in this module must have a generated lecture quiz before generating the module quiz.
              </p>
            </div>

            <form
              id="generate-questions-form"
              phx-submit="generate"
              phx-change="validate"
              class="mt-4 space-y-6"
            >
              <div class="grid grid-cols-1 gap-6 md:grid-cols-2 min-w-0">
                <div class="min-w-0 rounded-2xl border border-black/5 bg-surface/50 p-5 space-y-3 flex flex-col justify-between overflow-hidden">
                  <div class="min-w-0">
                    <h3 class="font-semibold text-ink flex items-center gap-2">
                      <.icon name="hero-rectangle-stack" class="h-5 w-5 text-primary shrink-0" />
                      Module resources
                    </h3>
                    <p class="mt-1 text-xs text-body">
                      Select video transcripts and attached documents from this module to feed as source context.
                    </p>

                    <fieldset class="mt-3 space-y-2 min-w-0">
                      <label
                        :for={lecture <- @module_video_lectures}
                        class="flex items-center gap-2.5 rounded-xl border border-black/5 bg-white p-3 text-sm text-ink transition hover:border-black/10 cursor-pointer min-w-0 max-w-full overflow-hidden"
                      >
                        <input
                          type="checkbox"
                          name="resources[]"
                          value={"video:#{lecture.id}"}
                          checked={"video:#{lecture.id}" in @selected_resources}
                          disabled={not @module_ready?}
                          class="shrink-0 rounded border-black/20 text-primary focus:ring-primary disabled:cursor-not-allowed disabled:opacity-50"
                        />
                        <span class="min-w-0 flex-1 truncate font-medium" title={lecture.title}>
                          {lecture.title} <span class="text-xs text-muted shrink-0">(video)</span>
                        </span>
                      </label>

                      <label
                        :for={resource <- @module_document_resources}
                        class="flex items-center gap-2.5 rounded-xl border border-black/5 bg-white p-3 text-sm text-ink transition hover:border-black/10 cursor-pointer min-w-0 max-w-full overflow-hidden"
                      >
                        <input
                          type="checkbox"
                          name="resources[]"
                          value={"doc:#{resource.id}"}
                          checked={"doc:#{resource.id}" in @selected_resources}
                          disabled={not @module_ready?}
                          class="shrink-0 rounded border-black/20 text-primary focus:ring-primary disabled:cursor-not-allowed disabled:opacity-50"
                        />
                        <span class="min-w-0 flex-1 truncate font-medium" title={resource.name}>
                          {resource.name}
                        </span>
                      </label>

                      <p
                        :if={@module_video_lectures == [] and @module_document_resources == []}
                        class="text-xs text-muted py-2"
                      >
                        No lecture resources found in this module.
                      </p>
                    </fieldset>
                  </div>
                </div>

                <div class="min-w-0 rounded-2xl border border-black/5 bg-surface/50 p-5 space-y-3 flex flex-col justify-between overflow-hidden">
                  <div>
                    <h3 class="font-semibold text-ink flex items-center gap-2">
                      <.icon name="hero-document-text" class="h-5 w-5 text-primary" />
                      Custom document upload
                    </h3>
                    <p class="mt-1 text-xs text-body">
                      Upload a PDF or DOCX file (up to 25MB) to generate questions directly from document text.
                    </p>

                    <div class="mt-4">
                      <div class={[@uploads.source_pdf.entries != [] && "hidden", "flex items-center"]}>
                        <label class={[
                          "inline-flex items-center gap-2 rounded-full px-5 py-2.5 text-sm font-semibold transition active:scale-[0.96]",
                          @module_ready? && "cursor-pointer bg-primary text-white hover:bg-ink",
                          !@module_ready? && "cursor-not-allowed bg-neutral-200 text-muted"
                        ]}>
                          <.icon name="hero-document-arrow-up" class="h-4 w-4" /> Select file
                          <.live_file_input
                            upload={@uploads.source_pdf}
                            disabled={not @module_ready?}
                            class="sr-only"
                          />
                        </label>
                      </div>

                      <div :if={@uploads.source_pdf.entries != []} class="space-y-3">
                        <div
                          :for={entry <- @uploads.source_pdf.entries}
                          class="flex items-center gap-3 rounded-xl border border-black/5 bg-white p-3 text-sm"
                        >
                          <span class="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-primary/10 text-primary">
                            <.icon name="hero-document" class="h-4 w-4" />
                          </span>
                          <div class="min-w-0 flex-1">
                            <div class="flex items-center justify-between gap-2">
                              <p class="truncate font-medium text-ink text-xs">
                                {entry.client_name}
                              </p>
                              <span class="shrink-0 text-xs tabular-nums text-muted">
                                {entry.progress}%
                              </span>
                            </div>
                            <div class="mt-1.5 h-1 overflow-hidden rounded-full bg-neutral-100">
                              <div
                                class="h-full rounded-full bg-primary transition-[width]"
                                style={"width: #{entry.progress}%"}
                                role="progressbar"
                                aria-valuemin="0"
                                aria-valuemax="100"
                                aria-valuenow={entry.progress}
                                value={entry.progress}
                              >
                              </div>
                            </div>
                            <p
                              :for={err <- upload_errors(@uploads.source_pdf, entry)}
                              class="mt-1 text-xs text-red-600"
                            >
                              {error_to_string(err)}
                            </p>
                          </div>
                          <button
                            type="button"
                            phx-click="cancel-upload"
                            phx-value-ref={entry.ref}
                            aria-label={"Remove #{entry.client_name}"}
                            class="grid h-7 w-7 shrink-0 place-items-center rounded-full text-muted transition hover:bg-red-50 hover:text-red-500 active:scale-[0.96]"
                          >
                            <.icon name="hero-x-mark" class="h-4 w-4" />
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <div class="flex justify-end pt-2">
                <button
                  type="submit"
                  disabled={
                    not @module_ready? or
                      (@selected_resources == [] and @uploads.source_pdf.entries == [])
                  }
                  title={
                    if not @module_ready?,
                      do:
                        "Every lecture in this module must have a generated lecture quiz before generating the module quiz.",
                      else: "Generate module quiz"
                  }
                  class="inline-flex items-center gap-2 rounded-full bg-ink px-6 py-3 text-sm font-semibold text-white transition hover:bg-primary active:scale-[0.96] disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-ink disabled:active:scale-100"
                >
                  <.icon name="hero-arrow-path" class="h-4 w-4" /> Generate module quiz
                </button>
              </div>
            </form>

            <div
              :if={active_generation(@generations)}
              class="flex items-center gap-4 rounded-3xl border border-primary/20 bg-mint/40 p-6"
            >
              <span class="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-white text-primary shadow-sm">
                <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin" />
              </span>
              <div>
                <p class="font-semibold text-ink">
                  Generating questions from {active_generation(@generations).source_filename}…
                </p>
                <p class="mt-0.5 text-sm text-body">
                  Extracting the document's text and drafting multiple-choice questions with AI.
                  This usually takes a minute or two — the draft questions will appear below once
                  they're ready.
                </p>
              </div>
            </div>

            <details :if={@generations != []} open class="group rounded-2xl border border-black/5 p-5">
              <summary class="flex cursor-pointer list-none items-center justify-between gap-3 [&::-webkit-details-marker]:hidden">
                <span class="flex items-center gap-2">
                  <h3 class="font-semibold text-ink">Generation history</h3>
                  <span class="rounded-full bg-surface px-2 py-0.5 text-xs font-semibold text-body">
                    {length(@generations)}
                  </span>
                </span>
                <.icon
                  name="hero-chevron-down"
                  class="h-4 w-4 shrink-0 text-muted transition group-open:rotate-180"
                />
              </summary>
              <ul class="mt-4 space-y-2">
                <li
                  :for={generation <- @generations}
                  class="flex items-center justify-between gap-3 rounded-xl border border-black/5 px-4 py-3 text-sm"
                >
                  <div class="min-w-0">
                    <p class="truncate font-medium text-ink">{generation.source_filename}</p>
                    <p class="mt-0.5 text-xs text-muted">{relative_time(generation.inserted_at)}</p>
                    <p :if={generation.status == :failed} class="mt-0.5 text-xs text-red-600">
                      {generation.error_message}
                    </p>
                  </div>
                  <div class="flex shrink-0 items-center gap-3">
                    <button
                      :if={draft_count_for_generation(@quiz, generation.id) > 0}
                      phx-click="confirm_discard_generation"
                      phx-value-id={generation.id}
                      class="text-xs font-medium text-muted hover:text-red-500"
                    >
                      Discard {draft_count_for_generation(@quiz, generation.id)} draft(s)
                    </button>
                    <.generation_status_badge
                      status={generation.status}
                      generated_count={generation.questions_generated_count}
                      remaining_count={draft_count_for_generation(@quiz, generation.id)}
                    />
                  </div>
                </li>
              </ul>
            </details>
          </div>
        </details>

        <section id="questions-section" class="space-y-6">
          <div class="flex flex-wrap items-center justify-between gap-4 border-b border-black/5 pb-4">
            <div>
              <h2 class="text-xl font-semibold text-ink">Questions</h2>
              <p class="mt-0.5 text-xs text-body">
                {length(@quiz.questions)} question(s) {if draft_questions(@quiz) != [],
                  do: "· #{length(draft_questions(@quiz))} draft(s)"}
              </p>
            </div>

            <div class="flex flex-wrap items-center gap-3">
              <button
                :if={draft_questions(@quiz) != []}
                type="button"
                phx-click="confirm_publish_all_drafts"
                class="rounded-full bg-mint px-4 py-2 text-xs font-semibold text-primary transition hover:bg-emerald-200 active:scale-[0.96]"
              >
                Publish all drafts
              </button>
              <button
                :if={draft_questions(@quiz) != []}
                type="button"
                phx-click="confirm_delete_all_drafts"
                class="rounded-full border border-black/10 px-4 py-2 text-xs font-medium text-muted transition hover:border-red-300 hover:text-red-600 active:scale-[0.96]"
              >
                Delete all drafts
              </button>

              <button
                id="add-true-false-question"
                type="button"
                phx-click="new_question"
                phx-value-type="true_false"
                class="inline-flex items-center gap-2 rounded-full border border-black/10 px-4 py-2 text-sm font-medium text-ink transition hover:border-primary hover:text-primary active:scale-[0.96]"
              >
                <.icon name="hero-plus" class="h-4 w-4" /> Add True/False question
              </button>
              <button
                id="add-question"
                type="button"
                phx-click="new_question"
                class="inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-ink active:scale-[0.96]"
              >
                <.icon name="hero-plus" class="h-4 w-4" /> Add multiple-choice question
              </button>
            </div>
          </div>

          <div
            id="quiz-questions"
            phx-hook="SortableList"
            data-event="reorder_questions"
            data-order-key="ids"
            class="space-y-5"
          >
            <article
              :for={{question, index} <- Enum.with_index(@quiz.questions, 1)}
              id={"question-#{question.id}"}
              data-sortable-item
              data-id={question.id}
              class="rounded-3xl border border-black/5 bg-white p-6 shadow-card data-[dragging=true]:opacity-50 lg:p-8"
            >
              <div class="mb-5 flex items-center justify-between gap-4">
                <div class="flex items-center gap-3">
                  <button
                    type="button"
                    data-sortable-handle
                    title="Drag to reorder"
                    class="cursor-grab rounded-lg p-2 text-muted hover:bg-surface hover:text-ink active:cursor-grabbing"
                  >
                    <.icon name="hero-bars-3" class="h-5 w-5" />
                  </button>
                  <h2 class="font-semibold text-ink">Question {index}</h2>
                  <span class={[
                    "rounded-full px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wider",
                    question.status == :published && "bg-mint text-primary",
                    question.status == :draft && "bg-surface text-body"
                  ]}>
                    {Phoenix.Naming.humanize(question.status)}
                  </span>
                </div>
                <div class="flex items-center gap-4">
                  <button
                    :if={question.status == :draft}
                    type="button"
                    phx-click="publish_question"
                    phx-value-id={question.id}
                    class="inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:text-ink transition active:scale-[0.96]"
                  >
                    <.icon name="hero-check-circle" class="h-4 w-4" /> Publish
                  </button>
                  <button
                    type="button"
                    phx-click="confirm_delete_question"
                    phx-value-id={question.id}
                    class="inline-flex items-center gap-1.5 text-sm font-medium text-red-500 hover:text-red-700 transition active:scale-[0.96]"
                  >
                    <.icon name="hero-trash" class="h-4 w-4" /> Remove
                  </button>
                </div>
              </div>

              <.question_form
                form={Map.fetch!(@question_forms, question.id)}
                question={question}
                dirty={MapSet.member?(@dirty_question_ids, question.id)}
              />
            </article>
          </div>

          <section
            :if={@quiz.questions == []}
            id="empty-quiz"
            class="rounded-3xl border border-dashed border-black/10 bg-white p-10 text-center"
          >
            <p class="font-medium text-ink">This quiz has no questions yet.</p>
            <p class="mt-1 text-sm text-body">
              Add your first question manually or generate from resources above.
            </p>
            <div class="mt-5 flex justify-center">
              <button
                type="button"
                phx-click="new_question"
                class="inline-flex items-center gap-2 rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-ink active:scale-[0.96]"
              >
                <.icon name="hero-plus" class="h-4 w-4" /> Add question
              </button>
            </div>
          </section>
        </section>
      </div>

      <.modal
        :if={@new_question_form}
        id="new-question-modal"
        show
        dismissable={false}
        max_width="max-w-3xl"
        on_cancel={JS.push("cancel_new_question")}
      >
        <h2 id="new-question-modal-title" class="mb-5 text-lg font-semibold text-ink">
          {if @new_question_type == "true_false",
            do: "New True/False question",
            else: "New multiple-choice question"}
        </h2>
        <.question_form form={@new_question_form} question={nil} />
      </.modal>

      <.confirm_modal
        :if={@deleting_question_id}
        id="delete-question-modal"
        title="Remove this question?"
        confirm_label="Remove"
        confirm={JS.push("delete_question", value: %{id: @deleting_question_id})}
        cancel={JS.push("cancel_delete_question")}
      >
        This can't be undone.
      </.confirm_modal>

      <.confirm_modal
        :if={@discarding_generation_id}
        id="discard-generation-modal"
        title="Discard this batch's draft questions?"
        confirm_label="Discard drafts"
        confirm={JS.push("discard_generation_drafts", value: %{id: @discarding_generation_id})}
        cancel={JS.push("cancel_discard_generation")}
      >
        This can't be undone. Only unpublished drafts from this specific generation are
        removed — published questions and other batches are untouched.
      </.confirm_modal>

      <.confirm_modal
        :if={@confirming_delete_all?}
        id="delete-all-drafts-modal"
        title="Delete all draft questions?"
        confirm_label="Delete all"
        confirm={JS.push("delete_all_drafts")}
        cancel={JS.push("cancel_delete_all_drafts")}
      >
        This can't be undone. All {pluralize(length(draft_questions(@quiz)), "draft question")} will be deleted.
      </.confirm_modal>

      <.confirm_modal
        :if={@confirming_publish_all?}
        id="publish-all-drafts-modal"
        title="Publish all draft questions?"
        variant={:primary}
        confirm_label="Publish all"
        confirm={JS.push("publish_all_drafts")}
        cancel={JS.push("cancel_publish_all_drafts")}
      >
        Every draft on this quiz will become visible to learners immediately. Make sure
        you've reviewed all of them first.
      </.confirm_modal>
    </.admin_layout>
    """
  end

  defp load_quiz!(quiz_id, course_slug) do
    quiz = Assessments.get_quiz_with_questions!(quiz_id)
    course = Catalog.get_course_by_slug!(course_slug)

    if quiz.module.course_id == course.id do
      quiz
    else
      raise Ecto.NoResultsError, queryable: Assessments.Quiz
    end
  end

  defp assign_quiz(socket, quiz) do
    forms =
      Map.new(quiz.questions, fn question ->
        {question.id, to_form(Assessments.change_question(question))}
      end)

    module_ready? = Assessments.module_ready_for_quiz_generation?(quiz.module_id)

    lectures =
      Catalog.list_lectures_for_module(quiz.module_id) |> Wasomi.Repo.preload([:resources])

    document_resources =
      Enum.flat_map(lectures, fn lecture ->
        Enum.filter(lecture.resources, &(&1.kind == :document))
      end)

    video_lectures =
      Enum.filter(lectures, fn lecture ->
        is_binary(lecture.video_asset_id) and lecture.video_asset_id != ""
      end)

    default_resources =
      Enum.flat_map(video_lectures, fn lecture ->
        transcript = Catalog.get_lecture_transcript(lecture.id)
        if transcript && transcript.status == :ready, do: ["video:#{lecture.id}"], else: []
      end) ++ Enum.map(document_resources, fn r -> "doc:#{r.id}" end)

    socket
    |> assign(:quiz, quiz)
    |> assign(:module_ready?, module_ready?)
    |> assign(:module_video_lectures, video_lectures)
    |> assign(:module_document_resources, document_resources)
    |> assign(:default_resources, default_resources)
    |> assign_new(:selected_resources, fn -> default_resources end)
    |> assign(:question_forms, forms)
    |> assign(:dirty_question_ids, MapSet.new())
  end

  defp mark_dirty(socket, question_id) do
    assign(
      socket,
      :dirty_question_ids,
      MapSet.put(socket.assigns.dirty_question_ids, question_id)
    )
  end

  defp reload_quiz(socket) do
    quiz = load_quiz!(socket.assigns.quiz.id, socket.assigns.course_slug)
    assign_quiz(socket, quiz)
  end

  defp find_question!(quiz, id) do
    Enum.find(quiz.questions, &(to_string(&1.id) == to_string(id))) ||
      raise Ecto.NoResultsError, queryable: Question
  end

  defp correct_option_id(full_params, prefix),
    do: get_in(full_params, [prefix, "correct_option_id"])

  defp apply_correct_option(params, correct_option_id) do
    correct_index = to_string(correct_option_id)

    Map.update(params, "question_options", %{}, fn options ->
      Map.new(options, fn {index, option_attrs} ->
        {index, Map.put(option_attrs, "correct", index == correct_index)}
      end)
    end)
  end

  defp blank_options("true_false") do
    [
      %{label: "True", correct: false, position: 1},
      %{label: "False", correct: false, position: 2}
    ]
  end

  defp blank_options(_multiple_choice) do
    Enum.map(1..4, &%{label: "", correct: false, position: &1})
  end

  defp next_position(quiz) do
    quiz.questions
    |> Enum.map(& &1.position)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp start_generation(quiz, user, filename, path) do
    with {:ok, pdf_binary} <- File.read(path),
         {:ok, generation} <- Assessments.create_generation(quiz, user, filename),
         key = "quiz-generations/#{generation.id}.pdf",
         :ok <- storage().upload(key, pdf_binary) do
      %{
        "generation_id" => generation.id,
        "pdf_storage_key" => key
      }
      |> GenerateQuizFromPDFWorker.new()
      |> Oban.insert()

      generation
    end
  end

  defp storage,
    do: Application.get_env(:wasomi, :assessments_storage, Wasomi.Assessments.Storage.R2)

  defp draft_questions(quiz), do: Enum.filter(quiz.questions, &(&1.status == :draft))

  defp source_label(resource_keys, assigns) do
    labels =
      Enum.map(resource_keys, fn
        "video:" <> lecture_id_str ->
          lecture_id = String.to_integer(lecture_id_str)

          case Enum.find(assigns.module_video_lectures, &(&1.id == lecture_id)) do
            %{title: title} -> "#{title} (transcript)"
            nil -> "Lecture ##{lecture_id} transcript"
          end

        "doc:" <> resource_id_str ->
          resource_id = String.to_integer(resource_id_str)

          case Enum.find(assigns.module_document_resources, &(&1.id == resource_id)) do
            %{name: name} -> name
            nil -> "Resource ##{resource_id}"
          end

        _ ->
          "Selected resource"
      end)

    case labels do
      [] -> "No resources selected"
      labels -> Enum.join(labels, " + ")
    end
  end

  defp active_generation(generations),
    do: Enum.find(generations, &(&1.status in [:pending, :processing]))

  defp relative_time(%DateTime{} = datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> pluralize(div(seconds, 60), "minute") <> " ago"
      seconds < 86_400 -> pluralize(div(seconds, 3600), "hour") <> " ago"
      seconds < 604_800 -> pluralize(div(seconds, 86_400), "day") <> " ago"
      true -> Calendar.strftime(datetime, "%b %-d, %Y")
    end
  end

  defp draft_count_for_generation(quiz, generation_id) do
    Enum.count(quiz.questions, &(&1.status == :draft and &1.quiz_generation_id == generation_id))
  end

  defp error_to_string(:too_large), do: "File is too large (max 25MB)."
  defp error_to_string(:not_accepted), do: "Only PDF files are accepted."
  defp error_to_string(:too_many_files), do: "Only one file at a time."
  defp error_to_string(other), do: to_string(other)

  attr :status, :atom, required: true
  attr :generated_count, :integer, default: nil
  attr :remaining_count, :integer, default: 0

  defp generation_status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium",
      @status == :ready && @remaining_count > 0 && "bg-mint text-primary",
      @status == :ready && @remaining_count == 0 && "bg-surface text-body",
      @status == :failed && "bg-red-50 text-red-600",
      @status in [:pending, :processing] && "bg-surface text-body"
    ]}>
      <.icon
        :if={@status in [:pending, :processing]}
        name="hero-arrow-path"
        class="h-3 w-3 animate-spin"
      />
      {generation_status_label(@status, @generated_count, @remaining_count)}
    </span>
    """
  end

  defp generation_status_label(:ready, generated_count, remaining_count)
       when remaining_count > 0 do
    "#{generated_count} generated · #{remaining_count} to review"
  end

  defp generation_status_label(:ready, generated_count, 0) do
    "#{generated_count} generated · reviewed"
  end

  defp generation_status_label(status, _generated_count, _remaining_count),
    do: Phoenix.Naming.humanize(status)
end
