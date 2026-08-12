defmodule WasomiWeb.AdminLive.LectureQuizEdit do
  use WasomiWeb, :live_view

  alias Wasomi.Assessments
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

    {:ok,
     socket
     |> assign(:page_title, "Lecture quiz")
     |> assign(:course_slug, course_slug)
     |> assign(:lecture, lecture)
     |> assign(:document_resources, Enum.filter(lecture.resources, &(&1.kind == :document)))
     |> assign(:transcript, Catalog.get_lecture_transcript(lecture.id))
     |> assign(:default_resources, default_resources(lecture))
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
    {:noreply, assign(socket, :transcript, transcript)}
  end

  @impl true
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

    attrs = %{
      difficulty: Map.get(params, "difficulty", "mixed"),
      question_count_requested: parse_count(Map.get(params, "question_count")),
      resource_selection: resource_keys,
      source_label: source_label(resource_keys, socket.assigns)
    }

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
          class="inline-flex items-center gap-1.5 text-sm font-medium text-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left-mini" class="h-4 w-4" /> Back to course
        </.link>

        <header>
          <p class="text-sm font-semibold uppercase tracking-wider text-primary">Lecture quiz</p>
          <h1 class="mt-2 text-3xl font-semibold text-dark">{@lecture.title}</h1>
        </header>

        <section class="rounded-3xl border border-black/5 bg-white p-6">
          <h2 class="text-lg font-semibold text-dark">Generate questions</h2>
          <p class="mt-1 text-sm text-body">
            Pick which of this lecture's resources should feed the AI, choose a difficulty and
            how many questions to draft, then review them below before publishing.
          </p>

          <form id="generate-lecture-quiz-form" phx-submit="generate" class="mt-5 space-y-5">
            <fieldset class="space-y-2">
              <legend class="text-sm font-medium text-dark">Resources</legend>

              <div
                :if={@lecture.video_asset_id}
                class="flex items-center justify-between gap-3 rounded-xl border border-black/5 px-4 py-2.5"
              >
                <label class="flex items-center gap-2 text-sm text-dark">
                  <input
                    type="checkbox"
                    name="resources[]"
                    value="video"
                    checked={"video" in @default_resources}
                    class="rounded border-black/20 text-primary focus:ring-primary"
                  /> Primary video
                  <span class="text-xs text-muted">
                    (uses the transcript, not the raw video — {transcript_status_label(@transcript)})
                  </span>
                </label>
                <button
                  :if={transcript_needs_generation?(@transcript)}
                  type="button"
                  phx-click="generate_transcript"
                  class="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-black/10 px-3 py-1.5 text-xs font-medium text-dark transition hover:border-primary hover:text-primary"
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
                class="flex items-center gap-2 rounded-xl border border-black/5 px-4 py-2.5 text-sm text-dark"
              >
                <input
                  type="checkbox"
                  name="resources[]"
                  value={resource.id}
                  class="rounded border-black/20 text-primary focus:ring-primary"
                />
                {resource.name}
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
                class="inline-flex items-center gap-2 rounded-full bg-dark px-6 py-3 text-sm font-semibold text-white transition hover:bg-primary"
              >
                <.icon name="hero-sparkles" class="h-4 w-4" /> Generate lecture quiz
              </button>
            </div>
          </form>

          <div
            :if={active_generation(@generations)}
            class="mt-5 flex items-center gap-4 rounded-3xl border border-primary/20 bg-mint/40 p-6"
          >
            <span class="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-white text-primary shadow-sm">
              <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin" />
            </span>
            <p class="font-semibold text-dark">
              Generating {active_generation(@generations).question_count_requested} questions from {active_generation(
                @generations
              ).source_label}…
            </p>
          </div>

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

        <section :if={@lecture_quiz} class="rounded-3xl border border-black/5 bg-white p-6">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 class="text-lg font-semibold text-dark">Questions</h2>
            <div :if={draft_questions(@lecture_quiz) != []} class="flex items-center gap-3">
              <button
                type="button"
                phx-click="confirm_delete_all"
                class="text-sm font-medium text-muted hover:text-red-500"
              >
                Delete all drafts
              </button>
              <button
                type="button"
                phx-click="confirm_publish_all"
                class="rounded-full bg-dark px-4 py-2 text-sm font-semibold text-white hover:bg-primary"
              >
                Publish all drafts
              </button>
            </div>
          </div>

          <p :if={@lecture_quiz.questions == []} class="mt-4 text-sm text-muted">
            No questions yet — generate some above.
          </p>

          <ul class="mt-4 space-y-3">
            <li
              :for={question <- @lecture_quiz.questions}
              class="rounded-2xl border border-black/5 p-4"
            >
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <span class={[
                    "mb-1.5 inline-block rounded-full px-2 py-0.5 text-xs font-medium",
                    question.status == :published && "bg-mint text-primary",
                    question.status == :draft && "bg-neutral-50 text-body"
                  ]}>
                    {Phoenix.Naming.humanize(question.status)}
                  </span>
                  <p class="font-medium text-dark">{question.prompt}</p>
                  <ul class="mt-2 space-y-1 text-sm text-body">
                    <li :for={option <- question.question_options} class="flex items-center gap-2">
                      <.icon
                        :if={option.correct}
                        name="hero-check-circle-solid"
                        class="h-4 w-4 shrink-0 text-primary"
                      />
                      <span :if={!option.correct} class="h-4 w-4 shrink-0"></span>
                      {option.label}
                    </li>
                  </ul>
                </div>
                <div class="flex shrink-0 items-center gap-1.5">
                  <button
                    :if={question.status == :draft}
                    type="button"
                    phx-click="publish_question"
                    phx-value-id={question.id}
                    class="rounded-full border border-black/10 px-3 py-1.5 text-xs font-medium text-dark hover:border-primary hover:text-primary"
                  >
                    Publish
                  </button>
                  <button
                    type="button"
                    phx-click="confirm_delete_question"
                    phx-value-id={question.id}
                    class="grid h-8 w-8 place-items-center rounded-full text-muted transition hover:bg-red-50 hover:text-red-500"
                    title="Delete question"
                  >
                    <.icon name="hero-trash" class="h-4 w-4" />
                  </button>
                </div>
              </div>
            </li>
          </ul>
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
    socket |> assign(:lecture_quiz, nil) |> assign(:generations, [])
  end

  defp assign_lecture_quiz(socket, lecture_quiz) do
    loaded = Assessments.get_lecture_quiz_with_questions!(lecture_quiz.id)

    socket
    |> assign(:lecture_quiz, loaded)
    |> assign(:generations, Assessments.list_lecture_quiz_generations(loaded))
  end

  defp reload(socket) do
    lecture_quiz = Assessments.get_lecture_quiz(socket.assigns.lecture.id)
    assign_lecture_quiz(socket, lecture_quiz)
  end

  defp default_resources(%{video_asset_id: asset_id}) when is_binary(asset_id) and asset_id != "",
    do: ["video"]

  defp default_resources(_lecture), do: []

  defp draft_questions(lecture_quiz),
    do: Enum.filter(lecture_quiz.questions, &(&1.status == :draft))

  defp active_generation(generations),
    do: Enum.find(generations, &(&1.status in [:pending, :processing]))

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
end
