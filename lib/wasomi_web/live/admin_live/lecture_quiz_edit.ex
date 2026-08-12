defmodule WasomiWeb.AdminLive.LectureQuizEdit do
  use WasomiWeb, :live_view

  alias Wasomi.Assessments
  alias Wasomi.Assessments.LectureQuizQuestion
  alias Wasomi.Catalog
  alias Wasomi.Catalog.Workers.TranscribeLecture

  @impl true
  def mount(%{"course_slug" => course_slug, "lecture_id" => lecture_id}, _session, socket) do
    lecture = load_lecture!(lecture_id, course_slug)
    lecture_quiz = Assessments.get_lecture_quiz(lecture.id)

    if connected?(socket) do
      if lecture_quiz, do: Assessments.subscribe_to_lecture_quiz_generation(lecture_quiz)
      Catalog.subscribe_to_lecture_transcript(lecture.id)
    end

    transcript = Catalog.get_lecture_transcript(lecture.id)

    defaults = default_resources(lecture, transcript)

    {:ok,
     socket
     |> assign(:page_title, "Lecture quiz")
     |> assign(:course_slug, course_slug)
     |> assign(:lecture, lecture)
     |> assign(:document_resources, Enum.filter(lecture.resources, &(&1.kind == :document)))
     |> assign(:transcript, transcript)
     |> assign(:default_resources, defaults)
     |> assign(:selected_resources, defaults)
     |> assign(:deleting_question_id, nil)
     |> assign(:confirming_publish_all?, false)
     |> assign(:confirming_delete_all?, false)
     |> assign_lecture_quiz(lecture_quiz)}
  end

  @impl true
  def handle_info({:lecture_quiz_generation_updated, _generation}, socket) do
    {:noreply, reload(socket)}
  end

  def handle_info({:lecture_transcript_updated, transcript}, socket) do
    defaults = default_resources(socket.assigns.lecture, transcript)

    {:noreply,
     socket
     |> assign(:transcript, transcript)
     |> assign(:default_resources, defaults)
     |> update(:selected_resources, fn
       [] -> defaults
       selected -> selected
     end)}
  end

  @impl true
  def handle_event("validate", params, socket) do
    resource_keys = params |> Map.get("resources", []) |> List.wrap()
    {:noreply, assign(socket, :selected_resources, resource_keys)}
  end

  def handle_event("generate_transcript", _params, socket) do
    lecture = socket.assigns.lecture
    {:ok, transcript} = Catalog.upsert_lecture_transcript(lecture.id, %{status: :pending})
    TranscribeLecture.enqueue(lecture.id)

    {:noreply,
     socket
     |> assign(:transcript, transcript)
     |> put_flash(:info, "Generating transcript in the background…")}
  end

  def handle_event("generate", params, socket) do
    lecture = socket.assigns.lecture
    resource_keys = params |> Map.get("resources", []) |> List.wrap()

    if "video" in resource_keys and !transcript_ready?(socket.assigns.transcript) do
      {:noreply,
       put_flash(
         socket,
         :error,
         "The primary video's transcript isn't ready yet — generate it first."
       )}
    else
      attrs = %{
        difficulty: Map.get(params, "difficulty", "mixed"),
        question_count_requested: parse_count(Map.get(params, "question_count")),
        resource_selection: resource_keys,
        source_label: source_label(resource_keys, socket.assigns)
      }

      do_generate(lecture, attrs, socket)
    end
  end

  def handle_event("validate_question", params, socket) do
    id = String.to_integer(params["id"])
    question = find_question!(socket.assigns.lecture_quiz, id)
    q_params = Map.get(params, "lecture_quiz_question", Map.get(params, "question", %{}))
    q_params = apply_correct_option(q_params, correct_option_id(params, "question-#{id}"))

    changeset =
      question
      |> Assessments.change_lecture_quiz_question(q_params)
      |> Map.put(:action, :validate)

    forms = Map.put(socket.assigns.question_forms, question.id, to_form(changeset))

    {:noreply,
     socket
     |> assign(:question_forms, forms)
     |> mark_dirty(question.id)}
  end

  def handle_event("validate_new_question", params, socket) do
    q_params = Map.get(params, "lecture_quiz_question", Map.get(params, "question", %{}))
    q_params = apply_correct_option(q_params, correct_option_id(params, "new-question"))

    quiz_id = if socket.assigns.lecture_quiz, do: socket.assigns.lecture_quiz.id, else: nil

    changeset =
      %LectureQuizQuestion{lecture_quiz_id: quiz_id}
      |> Assessments.change_lecture_quiz_question(q_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :new_question_form, to_form(changeset))}
  end

  def handle_event("add_option", %{"id" => "new"}, socket) do
    changeset = socket.assigns.new_question_form.source
    options = get_active_options(changeset)

    if length(options) < 4 do
      new_position = length(options) + 1

      new_option = %Wasomi.Assessments.LectureQuizQuestionOption{
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

      new_option = %Wasomi.Assessments.LectureQuizQuestionOption{
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

  def handle_event("save_question", params, socket) do
    id = String.to_integer(params["id"])
    question = find_question!(socket.assigns.lecture_quiz, id)
    q_params = Map.get(params, "lecture_quiz_question", Map.get(params, "question", %{}))
    q_params = apply_correct_option(q_params, correct_option_id(params, "question-#{id}"))

    case Assessments.update_lecture_quiz_question(question, q_params) do
      {:ok, _question} ->
        {:noreply,
         socket
         |> put_flash(:info, "Question saved.")
         |> unmark_dirty(question.id)
         |> reload()}

      {:error, changeset} ->
        forms =
          Map.put(socket.assigns.question_forms, question.id, to_form(changeset, action: :insert))

        {:noreply,
         socket
         |> assign(:question_forms, forms)
         |> mark_dirty(question.id)}
    end
  end

  def handle_event("new_question", params, socket) do
    type = Map.get(params, "type", "multiple_choice")

    quiz_id = if socket.assigns.lecture_quiz, do: socket.assigns.lecture_quiz.id, else: nil

    changeset =
      Assessments.change_lecture_quiz_question(%LectureQuizQuestion{lecture_quiz_id: quiz_id}, %{
        position: next_position(socket.assigns.lecture_quiz),
        status: :draft,
        question_options: blank_options(type)
      })

    {:noreply, assign(socket, :new_question_form, to_form(changeset))}
  end

  def handle_event("cancel_new_question", _params, socket) do
    {:noreply, assign(socket, :new_question_form, nil)}
  end

  def handle_event("save_new_question", params, socket) do
    q_params = Map.get(params, "lecture_quiz_question", Map.get(params, "question", %{}))

    {:ok, quiz} = Assessments.ensure_lecture_quiz(socket.assigns.lecture)

    q_params =
      q_params
      |> apply_correct_option(correct_option_id(params, "new-question"))
      |> Map.put("position", to_string(next_position(socket.assigns.lecture_quiz)))
      |> Map.put("status", "draft")

    case Assessments.create_lecture_quiz_question(quiz, q_params) do
      {:ok, _question} ->
        {:noreply,
         socket
         |> put_flash(:info, "Question added.")
         |> assign(:new_question_form, nil)
         |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_question_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("reorder_questions", %{"ids" => ids}, socket) do
    if socket.assigns.lecture_quiz do
      case Assessments.reorder_lecture_quiz_questions(socket.assigns.lecture_quiz, ids) do
        :ok ->
          {:noreply, reload(socket)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not reorder questions. Please try again.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("publish_question", %{"id" => id}, socket) do
    Assessments.get_lecture_quiz_question!(id) |> Assessments.publish_lecture_quiz_question()
    {:noreply, reload(socket)}
  end

  def handle_event("confirm_delete_question", %{"id" => id}, socket) do
    {:noreply, assign(socket, :deleting_question_id, id)}
  end

  def handle_event("cancel_delete_question", _params, socket) do
    {:noreply, assign(socket, :deleting_question_id, nil)}
  end

  def handle_event("delete_question", %{"id" => id}, socket) do
    Assessments.get_lecture_quiz_question!(id) |> Assessments.delete_lecture_quiz_question()
    {:noreply, socket |> assign(:deleting_question_id, nil) |> reload()}
  end

  def handle_event("confirm_publish_all", _params, socket) do
    {:noreply, assign(socket, :confirming_publish_all?, true)}
  end

  def handle_event("cancel_publish_all", _params, socket) do
    {:noreply, assign(socket, :confirming_publish_all?, false)}
  end

  def handle_event("publish_all_drafts", _params, socket) do
    Assessments.publish_all_lecture_quiz_drafts(socket.assigns.lecture_quiz)
    {:noreply, socket |> assign(:confirming_publish_all?, false) |> reload()}
  end

  def handle_event("confirm_delete_all", _params, socket) do
    {:noreply, assign(socket, :confirming_delete_all?, true)}
  end

  def handle_event("cancel_delete_all", _params, socket) do
    {:noreply, assign(socket, :confirming_delete_all?, false)}
  end

  def handle_event("delete_all_drafts", _params, socket) do
    Assessments.discard_all_lecture_quiz_drafts(socket.assigns.lecture_quiz)
    {:noreply, socket |> assign(:confirming_delete_all?, false) |> reload()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:courses} current_user={@current_user}>
      <div class="mx-auto max-w-4xl space-y-8 px-5 py-10 lg:px-8">
        <.link
          navigate={~p"/admin/courses/#{@course_slug}"}
          class="inline-flex items-center gap-1.5 text-sm font-medium text-muted hover:text-primary transition active:scale-[0.96]"
        >
          <.icon name="hero-arrow-left-mini" class="h-4 w-4" /> Back to course
        </.link>

        <header>
          <p class="text-sm font-semibold uppercase tracking-wider text-primary">Lecture quiz</p>
          <h1 class="mt-2 text-3xl font-semibold text-dark">{@lecture.title}</h1>
          <p class="mt-2 text-body">
            Edit questions inline and drag to reorder. Published questions are live immediately for learners.
          </p>
        </header>

        <section class="rounded-3xl border border-black/5 bg-white p-6 shadow-sm">
          <h2 class="text-lg font-semibold text-dark">Generate questions</h2>
          <p class="mt-1 text-sm text-body">
            Pick which of this lecture's resources should feed the AI, choose difficulty and question count.
          </p>

          <form
            id="generate-lecture-quiz-form"
            phx-change="validate"
            phx-submit="generate"
            class="mt-5 space-y-5"
          >
            <fieldset class="space-y-2 min-w-0">
              <legend class="text-sm font-medium text-dark">Resources</legend>

              <div
                :if={@lecture.video_asset_id}
                class="flex items-center justify-between gap-3 rounded-xl border border-black/5 px-4 py-2.5 min-w-0 max-w-full overflow-hidden"
              >
                <label class={[
                  "flex items-center gap-2 text-sm min-w-0 flex-1 truncate",
                  transcript_ready?(@transcript) && "text-dark",
                  !transcript_ready?(@transcript) && "text-muted"
                ]}>
                  <input
                    type="checkbox"
                    name="resources[]"
                    value="video"
                    checked={"video" in @selected_resources}
                    disabled={!transcript_ready?(@transcript)}
                    class="shrink-0 rounded border-black/20 text-primary focus:ring-primary disabled:cursor-not-allowed disabled:opacity-50"
                  />
                  <span class="truncate">
                    Primary video
                    <span class="text-xs text-muted">({transcript_status_label(@transcript)})</span>
                  </span>
                </label>
                <button
                  :if={transcript_needs_generation?(@transcript)}
                  type="button"
                  phx-click="generate_transcript"
                  class="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-black/10 px-3 py-1.5 text-xs font-medium text-dark transition hover:border-primary hover:text-primary active:scale-[0.96]"
                >
                  <.icon name="hero-document-text" class="h-3.5 w-3.5" />
                  {if @transcript && @transcript.status == :failed,
                    do: "Retry transcript",
                    else: "Generate transcript"}
                </button>
                <span
                  :if={@transcript && @transcript.status in [:pending, :processing]}
                  class="inline-flex shrink-0 items-center gap-1.5 text-xs text-muted"
                >
                  <.icon name="hero-arrow-path" class="h-3.5 w-3.5 animate-spin" /> Transcribing…
                </span>
              </div>

              <label
                :for={resource <- @document_resources}
                class="flex items-center gap-2 rounded-xl border border-black/5 px-4 py-2.5 text-sm text-dark min-w-0 max-w-full overflow-hidden"
              >
                <input
                  type="checkbox"
                  name="resources[]"
                  value={to_string(resource.id)}
                  checked={to_string(resource.id) in @selected_resources}
                  class="shrink-0 rounded border-black/20 text-primary focus:ring-primary"
                />
                <span class="truncate min-w-0 flex-1" title={resource.name}>{resource.name}</span>
              </label>

              <p
                :if={is_nil(@lecture.video_asset_id) and @document_resources == []}
                class="text-sm text-muted"
              >
                This lecture has no resources to generate from yet.
              </p>
            </fieldset>

            <div class="flex flex-wrap items-end gap-4">
              <div>
                <label for="difficulty" class="block text-sm font-medium text-dark">Difficulty</label>
                <select
                  id="difficulty"
                  name="difficulty"
                  class="mt-1 rounded-lg border border-black/10 px-3 py-2 text-sm focus:border-primary focus:ring-0"
                >
                  <option value="mixed" selected>Mixed</option>
                  <option value="easy">Easy</option>
                  <option value="medium">Medium</option>
                  <option value="hard">Hard</option>
                </select>
              </div>

              <div>
                <label for="question_count" class="block text-sm font-medium text-dark">
                  Number of questions
                </label>
                <input
                  type="number"
                  id="question_count"
                  name="question_count"
                  min="3"
                  max="25"
                  value="10"
                  class="mt-1 w-24 rounded-lg border border-black/10 px-3 py-2 text-sm focus:border-primary focus:ring-0"
                />
              </div>

              <button
                type="submit"
                disabled={@selected_resources == []}
                class="inline-flex items-center gap-2 rounded-full bg-dark px-6 py-3 text-sm font-semibold text-white transition hover:bg-primary active:scale-[0.96] disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-dark disabled:active:scale-100"
              >
                Generate lecture quiz
              </button>
            </div>
          </form>

          <ul :if={@generations != []} class="mt-5 space-y-2">
            <li
              :for={generation <- @generations}
              class="flex items-center justify-between gap-3 rounded-xl border border-black/5 px-4 py-3 text-sm"
            >
              <div class="min-w-0">
                <p class="truncate font-medium text-dark">{generation.source_label}</p>
                <p class="mt-0.5 text-xs text-muted">
                  {Phoenix.Naming.humanize(generation.difficulty)} · {generation.question_count_requested} questions requested
                </p>
                <p :if={generation.status == :failed} class="mt-0.5 text-xs text-red-600">
                  {generation.error_message}
                </p>
              </div>
              <.generation_status_badge
                status={generation.status}
                generated_count={generation.questions_generated_count}
              />
            </li>
          </ul>
        </section>

        <section id="questions-section" class="space-y-6">
          <div class="flex flex-wrap items-center justify-between gap-4 border-b border-black/5 pb-4">
            <div>
              <h2 class="text-xl font-semibold text-dark">Questions</h2>
              <p :if={@lecture_quiz} class="mt-0.5 text-xs text-body">
                {length(@lecture_quiz.questions)} question(s) {if draft_questions(@lecture_quiz) != [],
                                                                  do:
                                                                    "· #{length(draft_questions(@lecture_quiz))} draft(s)"}
              </p>
            </div>

            <div :if={is_nil(@new_question_form)} class="flex flex-wrap items-center gap-3">
              <button
                :if={@lecture_quiz && draft_questions(@lecture_quiz) != []}
                type="button"
                phx-click="confirm_publish_all"
                class="rounded-full bg-mint px-4 py-2 text-xs font-semibold text-primary transition hover:bg-emerald-200 active:scale-[0.96]"
              >
                Publish all drafts
              </button>
              <button
                :if={@lecture_quiz && draft_questions(@lecture_quiz) != []}
                type="button"
                phx-click="confirm_delete_all"
                class="rounded-full border border-black/10 px-4 py-2 text-xs font-medium text-muted transition hover:border-red-300 hover:text-red-600 active:scale-[0.96]"
              >
                Delete all drafts
              </button>

              <div class="inline-flex rounded-full bg-primary p-0.5 shadow-sm">
                <button
                  id="add-question"
                  type="button"
                  phx-click="new_question"
                  class="inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2 text-sm font-semibold text-white transition hover:bg-dark active:scale-[0.96]"
                >
                  <.icon name="hero-plus" class="h-4 w-4" /> Add question
                </button>
                <button
                  id="add-true-false-question"
                  type="button"
                  phx-click="new_question"
                  phx-value-type="true_false"
                  title="Add True/False question"
                  class="inline-flex items-center rounded-full px-3 py-2 text-xs font-medium text-white/90 transition hover:bg-dark hover:text-white active:scale-[0.96]"
                >
                  T/F
                </button>
              </div>
            </div>
          </div>

          <div
            :if={@lecture_quiz && @lecture_quiz.questions != []}
            id="quiz-questions"
            phx-hook="SortableList"
            data-event="reorder_questions"
            data-order-key="ids"
            class="space-y-5"
          >
            <article
              :for={{question, index} <- Enum.with_index(@lecture_quiz.questions, 1)}
              id={"question-#{question.id}"}
              data-sortable-item
              data-id={question.id}
              class="rounded-3xl border border-black/5 bg-white p-6 shadow-sm data-[dragging=true]:opacity-50 lg:p-8"
            >
              <div class="mb-5 flex items-center justify-between gap-4">
                <div class="flex items-center gap-3">
                  <button
                    type="button"
                    data-sortable-handle
                    title="Drag to reorder"
                    class="cursor-grab rounded-lg p-2 text-muted hover:bg-neutral-50 hover:text-dark active:cursor-grabbing"
                  >
                    <.icon name="hero-bars-3" class="h-5 w-5" />
                  </button>
                  <h2 class="font-semibold text-dark">Question {index}</h2>
                  <span class={[
                    "rounded-full px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wider",
                    question.status == :published && "bg-mint text-primary",
                    question.status == :draft && "bg-neutral-50 text-body"
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
                    class="inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:text-dark transition active:scale-[0.96]"
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
            :if={
              is_nil(@lecture_quiz) or (@lecture_quiz.questions == [] and is_nil(@new_question_form))
            }
            id="empty-quiz"
            class="rounded-3xl border border-dashed border-black/10 bg-white p-10 text-center"
          >
            <p class="font-medium text-dark">This lecture quiz has no questions yet.</p>
            <p class="mt-1 text-sm text-body">
              Add your first question manually or generate from lecture resources above.
            </p>
            <div class="mt-5 flex justify-center">
              <button
                type="button"
                phx-click="new_question"
                class="inline-flex items-center gap-2 rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-dark active:scale-[0.96]"
              >
                <.icon name="hero-plus" class="h-4 w-4" /> Add question
              </button>
            </div>
          </section>

          <section
            :if={@new_question_form}
            id="new-question"
            class="rounded-3xl border border-primary/20 bg-white p-6 shadow-sm lg:p-8"
          >
            <h2 class="mb-5 font-semibold text-dark">New question</h2>
            <.question_form form={@new_question_form} question={nil} />
          </section>
        </section>
      </div>

      <.confirm_modal
        :if={@deleting_question_id}
        id="delete-question-modal"
        title="Delete this question?"
        confirm={JS.push("delete_question", value: %{id: @deleting_question_id})}
        cancel={JS.push("cancel_delete_question")}
      >
        This can't be undone.
      </.confirm_modal>

      <.confirm_modal
        :if={@confirming_publish_all?}
        id="publish-all-modal"
        title="Publish all draft questions?"
        variant={:primary}
        confirm_label="Publish all"
        confirm={JS.push("publish_all_drafts")}
        cancel={JS.push("cancel_publish_all")}
      >
        Every draft question becomes visible to learners immediately.
      </.confirm_modal>

      <.confirm_modal
        :if={@confirming_delete_all?}
        id="delete-all-modal"
        title="Delete all draft questions?"
        confirm={JS.push("delete_all_drafts")}
        cancel={JS.push("cancel_delete_all")}
      >
        Published questions are unaffected. This can't be undone.
      </.confirm_modal>
    </.admin_layout>
    """
  end

  attr :status, :atom, required: true
  attr :generated_count, :integer, default: nil

  defp generation_status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium",
      @status == :ready && "bg-mint text-primary",
      @status == :failed && "bg-red-50 text-red-600",
      @status in [:pending, :processing] && "bg-neutral-50 text-body"
    ]}>
      <.icon
        :if={@status in [:pending, :processing]}
        name="hero-arrow-path"
        class="h-3 w-3 animate-spin"
      />
      {generation_status_label(@status, @generated_count)}
    </span>
    """
  end

  defp generation_status_label(:ready, generated_count), do: "#{generated_count} generated"
  defp generation_status_label(status, _generated_count), do: Phoenix.Naming.humanize(status)

  defp load_lecture!(lecture_id, course_slug) do
    course = Catalog.get_course_by_slug!(course_slug)

    lecture =
      Catalog.get_lecture!(lecture_id) |> Wasomi.Repo.preload([:resources, module: :course])

    if lecture.module.course_id == course.id do
      lecture
    else
      raise Ecto.NoResultsError, queryable: Catalog.Lecture
    end
  end

  defp assign_lecture_quiz(socket, nil) do
    socket
    |> assign(:lecture_quiz, nil)
    |> assign(:generations, [])
    |> assign(:question_forms, %{})
    |> assign(:dirty_question_ids, MapSet.new())
    |> assign(:new_question_form, nil)
  end

  defp assign_lecture_quiz(socket, lecture_quiz) do
    loaded = Assessments.get_lecture_quiz_with_questions!(lecture_quiz.id)

    forms =
      Map.new(loaded.questions, fn question ->
        {question.id, to_form(Assessments.change_lecture_quiz_question(question))}
      end)

    socket
    |> assign(:lecture_quiz, loaded)
    |> assign(:generations, Assessments.list_lecture_quiz_generations(loaded))
    |> assign(:question_forms, forms)
    |> assign_new(:dirty_question_ids, fn -> MapSet.new() end)
    |> assign_new(:new_question_form, fn -> nil end)
  end

  defp reload(socket) do
    lecture_quiz = Assessments.get_lecture_quiz(socket.assigns.lecture.id)
    assign_lecture_quiz(socket, lecture_quiz)
  end

  defp do_generate(lecture, attrs, socket) do
    case Assessments.start_lecture_quiz_generation(lecture, socket.assigns.current_user, attrs) do
      {:ok, _generation} ->
        {:noreply,
         socket
         |> put_flash(:info, "Generating draft questions in the background…")
         |> reload()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         put_flash(socket, :error, "Could not start generation: #{generation_error(changeset)}")}
    end
  end

  defp default_resources(%{video_asset_id: asset_id}, transcript)
       when is_binary(asset_id) and asset_id != "" do
    if transcript_ready?(transcript), do: ["video"], else: []
  end

  defp default_resources(_lecture, _transcript), do: []

  defp draft_questions(lecture_quiz),
    do: Enum.filter(lecture_quiz.questions, &(&1.status == :draft))

  defp parse_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {count, _} -> count |> max(3) |> min(25)
      :error -> 10
    end
  end

  defp parse_count(_value), do: 10

  defp transcript_status_label(%{status: :ready}), do: "transcript ready"
  defp transcript_status_label(%{status: status}), do: "transcript #{status}"
  defp transcript_status_label(nil), do: "transcript not started yet"

  defp transcript_needs_generation?(nil), do: true
  defp transcript_needs_generation?(%{status: status}), do: status == :failed

  defp transcript_ready?(%{status: :ready}), do: true
  defp transcript_ready?(_transcript), do: false

  defp source_label(resource_keys, assigns) do
    labels =
      Enum.map(resource_keys, fn
        "video" ->
          "primary video transcript"

        id ->
          case Enum.find(assigns.document_resources, &(to_string(&1.id) == id)) do
            %{name: name} -> name
            nil -> "resource ##{id}"
          end
      end)

    case labels do
      [] -> "no resources selected"
      labels -> Enum.join(labels, " + ")
    end
  end

  defp generation_error(changeset) do
    case changeset.errors[:resource_selection] do
      {message, _opts} -> String.capitalize(message) <> "."
      nil -> "Something went wrong. Please try again."
    end
  end

  defp find_question!(lecture_quiz, id) when is_integer(id) do
    Enum.find(lecture_quiz.questions, &(&1.id == id)) ||
      raise Ecto.NoResultsError, queryable: Wasomi.Assessments.LectureQuizQuestion
  end

  defp mark_dirty(socket, id) do
    update(socket, :dirty_question_ids, &MapSet.put(&1, id))
  end

  defp unmark_dirty(socket, id) do
    update(socket, :dirty_question_ids, &MapSet.delete(&1, id))
  end

  defp next_position(nil), do: 1

  defp next_position(%{questions: questions}) do
    questions
    |> Enum.map(& &1.position)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp blank_options("true_false") do
    [
      %{label: "True", correct: true, position: 1},
      %{label: "False", correct: false, position: 2}
    ]
  end

  defp blank_options(_type) do
    [
      %{label: "Option A", correct: true, position: 1},
      %{label: "Option B", correct: false, position: 2},
      %{label: "Option C", correct: false, position: 3},
      %{label: "Option D", correct: false, position: 4}
    ]
  end

  defp correct_option_id(params, prefix) do
    case params[prefix] do
      %{"correct_option_id" => id_str} -> parse_integer(id_str)
      _ -> nil
    end
  end

  defp apply_correct_option(params, nil), do: params

  defp apply_correct_option(%{"question_options" => options} = params, correct_index) do
    updated_options =
      options
      |> Enum.map(fn {key, option_params} ->
        is_correct = to_string(key) == to_string(correct_index)

        option_params =
          case option_params do
            %{} = map -> Map.put(map, "correct", is_correct)
            other -> other
          end

        {key, option_params}
      end)
      |> Map.new()

    Map.put(params, "question_options", updated_options)
  end

  defp apply_correct_option(params, _index), do: params

  defp parse_integer(val) when is_integer(val), do: val

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_integer(_), do: nil

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
end
