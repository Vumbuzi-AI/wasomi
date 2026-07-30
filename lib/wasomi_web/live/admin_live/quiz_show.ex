defmodule WasomiWeb.AdminLive.QuizShow do
  use WasomiWeb, :live_view

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Question
  alias Wasomi.Assessments.QuizGeneration
  alias Wasomi.Assessments.Workers.GenerateQuizFromPDFWorker

  @max_pdf_bytes 25_000_000

  @impl true
  def mount(%{"course_id" => course_id, "quiz_id" => quiz_id}, _session, socket) do
    quiz = Assessments.get_quiz_with_questions!(quiz_id)

    if to_string(quiz.module.course_id) != course_id do
      raise Ecto.NoResultsError, queryable: Assessments.Quiz
    end

    if connected?(socket), do: Assessments.subscribe_to_generation(quiz)

    {:ok,
     socket
     |> assign(:page_title, "Manage quiz")
     |> assign(:quiz, quiz)
     |> assign(:quiz_form, to_form(Assessments.change_quiz(quiz)))
     |> assign(:generations, Assessments.list_generations_for_quiz(quiz))
     |> assign(:editing_question_id, nil)
     |> assign(:adding_question?, false)
     |> assign(:question_form, nil)
     |> assign(:deleting_question_id, nil)
     |> assign(:discarding_generation_id, nil)
     |> assign(:confirming_delete_all?, false)
     |> assign(:confirming_publish_all?, false)
     |> allow_upload(:source_pdf,
       accept: ~w(.pdf),
       max_entries: 1,
       max_file_size: @max_pdf_bytes,
       auto_upload: true
     )}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :source_pdf, ref)}
  end

  def handle_event("update_quiz_settings", %{"quiz" => params}, socket) do
    quiz = socket.assigns.quiz

    case Assessments.update_quiz(quiz, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Quiz settings updated.")
         |> assign(:quiz, updated)
         |> assign(:quiz_form, to_form(Assessments.change_quiz(updated)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :quiz_form, to_form(changeset))}
    end
  end

  def handle_event("generate", _params, socket) do
    quiz = socket.assigns.quiz
    user = socket.assigns.current_user

    results =
      consume_uploaded_entries(socket, :source_pdf, fn %{path: path}, entry ->
        {:ok, start_generation(quiz, user, entry.client_name, path)}
      end)

    case results do
      [%QuizGeneration{}] ->
        {:noreply,
         socket
         |> put_flash(:info, "PDF uploaded. Generating draft questions in the background…")
         |> assign(:generations, Assessments.list_generations_for_quiz(quiz))}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, "Could not start generation: #{inspect(reason)}")}

      [] ->
        {:noreply, put_flash(socket, :error, "Choose a PDF file first.")}
    end
  end

  def handle_event("publish_question", %{"id" => id}, socket) do
    question = Assessments.get_question!(id)
    {:ok, _published} = Assessments.publish_question(question)

    {:noreply,
     socket
     |> put_flash(:info, "Question published.")
     |> assign(:quiz, Assessments.get_quiz_with_questions!(socket.assigns.quiz.id))}
  end

  def handle_event("edit_question", %{"id" => id}, socket) do
    question = find_question!(socket.assigns.quiz, id)

    {:noreply,
     socket
     |> assign(:editing_question_id, question.id)
     |> assign(:adding_question?, false)
     |> assign(:question_form, to_form(Assessments.change_question(question)))}
  end

  def handle_event("cancel_edit_question", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_question_id, nil)
     |> assign(:question_form, nil)}
  end

  def handle_event("save_question", %{"id" => id, "question" => params}, socket) do
    question = find_question!(socket.assigns.quiz, id)
    params = apply_correct_option(params)

    case Assessments.update_question(question, params) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Question updated.")
         |> assign(:editing_question_id, nil)
         |> assign(:question_form, nil)
         |> assign(:quiz, Assessments.get_quiz_with_questions!(socket.assigns.quiz.id))}

      {:error, changeset} ->
        {:noreply, assign(socket, :question_form, to_form(changeset))}
    end
  end

  def handle_event("new_question", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_question_id, nil)
     |> assign(:adding_question?, true)
     |> assign(:question_form, nil)}
  end

  def handle_event("choose_question_type", %{"type" => type}, socket) do
    quiz = socket.assigns.quiz

    changeset =
      Assessments.change_question(%Question{quiz_id: quiz.id}, %{
        question_options: blank_options(type)
      })

    {:noreply, assign(socket, :question_form, to_form(changeset))}
  end

  def handle_event("cancel_new_question", _params, socket) do
    {:noreply,
     socket
     |> assign(:adding_question?, false)
     |> assign(:question_form, nil)}
  end

  def handle_event("save_new_question", %{"question" => params}, socket) do
    quiz = socket.assigns.quiz

    params =
      params
      |> apply_correct_option()
      |> Map.put("position", to_string(next_question_position(quiz)))
      |> Map.put("status", "draft")

    case Assessments.create_question(quiz, params) do
      {:ok, _question} ->
        {:noreply,
         socket
         |> put_flash(:info, "Question added.")
         |> assign(:adding_question?, false)
         |> assign(:question_form, nil)
         |> assign(:quiz, Assessments.get_quiz_with_questions!(quiz.id))}

      {:error, changeset} ->
        {:noreply, assign(socket, :question_form, to_form(changeset))}
    end
  end

  def handle_event("confirm_delete_question", %{"id" => id}, socket) do
    {:noreply, assign(socket, :deleting_question_id, String.to_integer(id))}
  end

  def handle_event("cancel_delete_question", _params, socket) do
    {:noreply, assign(socket, :deleting_question_id, nil)}
  end

  def handle_event("delete_question", %{"id" => id}, socket) do
    question = Assessments.get_question!(id)
    {:ok, _deleted} = Assessments.delete_question(question)

    {:noreply,
     socket
     |> put_flash(:info, "Question deleted.")
     |> assign(:deleting_question_id, nil)
     |> assign(:quiz, Assessments.get_quiz_with_questions!(socket.assigns.quiz.id))}
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
     |> assign(:quiz, Assessments.get_quiz_with_questions!(socket.assigns.quiz.id))}
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
     |> assign(:quiz, Assessments.get_quiz_with_questions!(quiz.id))}
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
     |> assign(:quiz, Assessments.get_quiz_with_questions!(quiz.id))}
  end

  defp next_question_position(quiz) do
    quiz.questions
    |> Enum.map(& &1.position)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
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

  defp find_question!(quiz, id) do
    id = to_string(id)

    Enum.find(quiz.questions, &(to_string(&1.id) == id)) ||
      raise Ecto.NoResultsError, queryable: Question
  end

  defp apply_correct_option(params) do
    correct_index = to_string(params["correct_option_id"])

    Map.update(params, "question_options", %{}, fn options ->
      Map.new(options, fn {index, option_attrs} ->
        {index, Map.put(option_attrs, "correct", index == correct_index)}
      end)
    end)
  end

  @impl true
  def handle_info({:quiz_generation_updated, _generation}, socket) do
    quiz = socket.assigns.quiz

    {:noreply,
     socket
     |> assign(:generations, Assessments.list_generations_for_quiz(quiz))
     |> assign(:quiz, Assessments.get_quiz_with_questions!(quiz.id))}
  end

  defp start_generation(quiz, user, filename, path) do
    with {:ok, pdf_binary} <- File.read(path),
         {:ok, generation} <- Assessments.create_generation(quiz, user, filename) do
      %{
        "generation_id" => generation.id,
        "pdf_base64" => Base.encode64(pdf_binary)
      }
      |> GenerateQuizFromPDFWorker.new()
      |> Oban.insert()

      generation
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:courses} current_user={@current_user}>
      <div class="mx-auto max-w-3xl space-y-8 px-5 py-10 lg:px-8">
        <.link
          navigate={~p"/admin/courses/#{@quiz.module.course_id}"}
          class="inline-flex items-center gap-1.5 text-sm font-medium text-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left-mini" class="h-4 w-4" /> Back to course
        </.link>

        <div>
          <h1 class="text-2xl font-semibold text-dark">Manage quiz</h1>
          <p class="mt-1 text-body">{@quiz.title}</p>
        </div>

        <section class="rounded-3xl border border-black/5 bg-white p-6">
          <.form
            for={@quiz_form}
            id="quiz-settings-form"
            phx-submit="update_quiz_settings"
            class="flex flex-wrap items-center gap-4"
          >
            <label for={@quiz_form[:passing_score_percent].id} class="text-lg font-semibold text-dark">
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
                class="w-24 rounded-lg border border-black/10 px-3 py-2 text-sm text-dark focus:border-primary focus:ring-0"
              />
              <span class="text-sm text-body">%</span>
            </div>
            <button
              type="submit"
              class="rounded-full bg-dark px-5 py-2 text-sm font-medium text-white transition hover:bg-primary"
            >
              Save
            </button>
            <.field_error field={@quiz_form[:passing_score_percent]} />
          </.form>
        </section>

        <section class="rounded-3xl border border-black/5 bg-white p-6 lg:p-8">
          <h2 class="text-lg font-semibold text-dark">Upload a source PDF</h2>
          <p class="mt-1 text-sm text-body">
            Up to 25MB. Draft multiple-choice questions are generated in the background from the
            document's content and appear below for review before publishing.
          </p>

          <form id="generate-questions-form" phx-submit="generate" phx-change="validate" class="mt-5">
            <.live_file_input upload={@uploads.source_pdf} />

            <div
              :for={entry <- @uploads.source_pdf.entries}
              class="mt-3 flex items-center gap-3 text-sm"
            >
              <span class="text-dark">{entry.client_name}</span>
              <progress value={entry.progress} max="100" class="w-32"></progress>
              <button
                type="button"
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                class="text-muted hover:text-red-500"
              >
                <.icon name="hero-x-mark" class="h-4 w-4" />
              </button>
              <p :for={err <- upload_errors(@uploads.source_pdf, entry)} class="text-red-600">
                {error_to_string(err)}
              </p>
            </div>

            <button
              type="submit"
              class="mt-5 rounded-full bg-dark px-6 py-3 font-medium text-white transition hover:bg-primary"
            >
              Generate questions
            </button>
          </form>
        </section>

        <details
          :if={@generations != []}
          open
          class="group rounded-3xl border border-black/5 bg-white p-6"
        >
          <summary class="flex cursor-pointer list-none items-center justify-between gap-3 [&::-webkit-details-marker]:hidden">
            <span class="flex items-center gap-2">
              <h2 class="text-lg font-semibold text-dark">Generation history</h2>
              <span class="rounded-full bg-soft px-2 py-0.5 text-xs font-semibold text-body">
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
                <p class="truncate font-medium text-dark">{generation.source_filename}</p>
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

        <section class="rounded-3xl border border-black/5 bg-white p-6">
          <div class="flex items-center justify-between gap-3">
            <div class="flex items-center gap-3">
              <h2 class="text-lg font-semibold text-dark">Draft questions awaiting review</h2>
              <span
                :if={draft_questions(@quiz) != []}
                class="inline-flex items-center justify-center rounded-full bg-mint px-2.5 py-1 text-xs font-bold text-primary"
              >
                {length(draft_questions(@quiz))}
              </span>
            </div>
            <div class="flex items-center gap-3">
              <button
                :if={draft_questions(@quiz) != []}
                phx-click="confirm_publish_all_drafts"
                class="rounded-full bg-mint px-3 py-1.5 text-sm font-semibold text-primary transition hover:bg-primary hover:text-white"
              >
                Publish all
              </button>
              <button
                :if={draft_questions(@quiz) != []}
                phx-click="confirm_delete_all_drafts"
                class="rounded-full border border-black/10 px-3 py-1.5 text-sm font-medium text-body transition hover:border-red-200 hover:bg-red-50 hover:text-red-500"
              >
                Delete all
              </button>
              <button
                :if={!@adding_question?}
                phx-click="new_question"
                class="inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:text-dark"
              >
                <.icon name="hero-plus-circle" class="h-4 w-4" /> Add question
              </button>
            </div>
          </div>
          <p :if={draft_questions(@quiz) == [] and !@adding_question?} class="mt-3 text-sm text-body">
            No draft questions yet. Generate some from a PDF above, or add one manually.
          </p>

          <div
            :if={@adding_question? and is_nil(@question_form)}
            class="mt-4 flex items-center gap-3 rounded-2xl border border-black/5 p-5"
          >
            <span class="text-sm font-medium text-dark">Add a:</span>
            <button
              phx-click="choose_question_type"
              phx-value-type="multiple_choice"
              class="rounded-full border border-black/10 px-3 py-1.5 text-sm font-medium text-dark transition hover:border-primary hover:text-primary"
            >
              Multiple choice
            </button>
            <button
              phx-click="choose_question_type"
              phx-value-type="true_false"
              class="rounded-full border border-black/10 px-3 py-1.5 text-sm font-medium text-dark transition hover:border-primary hover:text-primary"
            >
              True/False
            </button>
            <button
              phx-click="cancel_new_question"
              class="ml-auto text-sm font-medium text-muted hover:text-dark"
            >
              Cancel
            </button>
          </div>

          <.form
            :if={@adding_question? and @question_form}
            for={@question_form}
            id="new-question-form"
            phx-submit="save_new_question"
            class="mt-4 space-y-3 rounded-2xl border border-black/5 p-5"
          >
            <.input field={@question_form[:prompt]} type="text" label="Question" />

            <div class="space-y-2">
              <p class="text-sm font-medium text-dark">Options (select the correct one)</p>
              <.question_options_fields
                field={@question_form[:question_options]}
                include_position?={true}
              />
            </div>

            <div class="flex items-center gap-4 pt-1">
              <button
                type="submit"
                class="rounded-full bg-dark px-5 py-2 text-sm font-medium text-white transition hover:bg-primary"
              >
                Save question
              </button>
              <button
                type="button"
                phx-click="cancel_new_question"
                class="text-sm font-medium text-muted hover:text-dark"
              >
                Cancel
              </button>
            </div>
          </.form>

          <ul class="mt-4 space-y-4">
            <li
              :for={question <- draft_questions(@quiz)}
              class="rounded-2xl border border-black/5 p-5"
            >
              <.form
                :if={@editing_question_id == question.id}
                for={@question_form}
                id={"question-form-#{question.id}"}
                phx-submit="save_question"
                phx-value-id={question.id}
                class="space-y-3"
              >
                <.input field={@question_form[:prompt]} type="text" label="Question" />

                <div class="space-y-2">
                  <p class="text-sm font-medium text-dark">Options (select the correct one)</p>
                  <.question_options_fields field={@question_form[:question_options]} />
                </div>

                <div class="flex items-center gap-4 pt-1">
                  <button
                    type="submit"
                    class="rounded-full bg-dark px-5 py-2 text-sm font-medium text-white transition hover:bg-primary"
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_edit_question"
                    class="text-sm font-medium text-muted hover:text-dark"
                  >
                    Cancel
                  </button>
                </div>
              </.form>

              <div :if={@editing_question_id != question.id}>
                <p class="font-semibold leading-relaxed text-dark">{question.prompt}</p>

                <ul class="mt-4 space-y-2">
                  <li
                    :for={{option, index} <- Enum.with_index(question.question_options)}
                    class={[
                      "flex items-start gap-3 rounded-xl border px-3.5 py-2.5 text-sm",
                      (option.correct && "border-primary/20 bg-mint/50") || "border-black/5"
                    ]}
                  >
                    <span class={[
                      "grid h-6 w-6 shrink-0 place-items-center rounded-full text-xs font-semibold",
                      (option.correct && "bg-primary text-white") || "bg-soft text-muted"
                    ]}>
                      {option_letter(index)}
                    </span>
                    <span class={[
                      "pt-0.5",
                      (option.correct && "font-medium text-dark") || "text-body"
                    ]}>
                      {option.label}
                    </span>
                    <.icon
                      :if={option.correct}
                      name="hero-check-circle-solid"
                      class="ml-auto h-5 w-5 shrink-0 text-primary"
                    />
                  </li>
                </ul>

                <div class="mt-5 flex items-center justify-between border-t border-black/5 pt-4">
                  <div class="flex items-center gap-3">
                    <button
                      phx-click="edit_question"
                      phx-value-id={question.id}
                      class="rounded-full border border-black/10 px-3 py-1.5 text-sm font-medium text-dark transition hover:border-black/20 hover:bg-soft"
                    >
                      Edit
                    </button>
                    <button
                      phx-click="publish_question"
                      phx-value-id={question.id}
                      class="rounded-full bg-mint px-3 py-1.5 text-sm font-semibold text-primary transition hover:bg-primary hover:text-white"
                    >
                      Publish
                    </button>
                  </div>
                  <button
                    phx-click="confirm_delete_question"
                    phx-value-id={question.id}
                    class="grid h-8 w-8 place-items-center rounded-full border border-black/10 text-red-500 transition hover:border-red-200 hover:bg-red-50"
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

      <.modal
        :if={@deleting_question_id}
        id="delete-question-modal"
        show
        on_cancel={JS.push("cancel_delete_question")}
      >
        <h2 class="text-lg font-semibold text-dark">Delete this draft question?</h2>
        <p class="mt-2 text-sm text-body">
          This can't be undone. The question and its options will be permanently removed.
        </p>
        <div class="mt-6 flex items-center gap-4">
          <button
            phx-click="delete_question"
            phx-value-id={@deleting_question_id}
            class="rounded-full bg-red-600 px-5 py-2 text-sm font-medium text-white transition hover:bg-red-700"
          >
            Delete
          </button>
          <button
            phx-click="cancel_delete_question"
            class="text-sm font-medium text-muted hover:text-dark"
          >
            Cancel
          </button>
        </div>
      </.modal>

      <.modal
        :if={@discarding_generation_id}
        id="discard-generation-modal"
        show
        on_cancel={JS.push("cancel_discard_generation")}
      >
        <h2 class="text-lg font-semibold text-dark">Discard this batch's draft questions?</h2>
        <p class="mt-2 text-sm text-body">
          This can't be undone. Only unpublished drafts from this specific generation are
          removed — published questions and other batches are untouched.
        </p>
        <div class="mt-6 flex items-center gap-4">
          <button
            phx-click="discard_generation_drafts"
            phx-value-id={@discarding_generation_id}
            class="rounded-full bg-red-600 px-5 py-2 text-sm font-medium text-white transition hover:bg-red-700"
          >
            Discard drafts
          </button>
          <button
            phx-click="cancel_discard_generation"
            class="text-sm font-medium text-muted hover:text-dark"
          >
            Cancel
          </button>
        </div>
      </.modal>

      <.modal
        :if={@confirming_delete_all?}
        id="delete-all-drafts-modal"
        show
        on_cancel={JS.push("cancel_delete_all_drafts")}
      >
        <h2 class="text-lg font-semibold text-dark">Delete all draft questions?</h2>
        <p class="mt-2 text-sm text-body">
          This can't be undone. Every unpublished draft on this quiz — from any generation
          batch, or added manually — will be permanently removed.
        </p>
        <div class="mt-6 flex items-center gap-4">
          <button
            phx-click="delete_all_drafts"
            class="rounded-full bg-red-600 px-5 py-2 text-sm font-medium text-white transition hover:bg-red-700"
          >
            Delete all
          </button>
          <button
            phx-click="cancel_delete_all_drafts"
            class="text-sm font-medium text-muted hover:text-dark"
          >
            Cancel
          </button>
        </div>
      </.modal>

      <.modal
        :if={@confirming_publish_all?}
        id="publish-all-drafts-modal"
        show
        on_cancel={JS.push("cancel_publish_all_drafts")}
      >
        <h2 class="text-lg font-semibold text-dark">Publish all draft questions?</h2>
        <p class="mt-2 text-sm text-body">
          Every draft on this quiz will become visible to learners immediately. Make sure
          you've reviewed all of them first.
        </p>
        <div class="mt-6 flex items-center gap-4">
          <button
            phx-click="publish_all_drafts"
            class="rounded-full bg-primary px-5 py-2 text-sm font-medium text-white transition hover:bg-dark"
          >
            Publish all
          </button>
          <button
            phx-click="cancel_publish_all_drafts"
            class="text-sm font-medium text-muted hover:text-dark"
          >
            Cancel
          </button>
        </div>
      </.modal>
    </.admin_layout>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp field_error(assigns) do
    errors = if Phoenix.Component.used_input?(assigns.field), do: assigns.field.errors, else: []
    assigns = assign(assigns, :errors, errors)

    ~H"""
    <.error :for={error <- @errors}>{translate_error(error)}</.error>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :include_position?, :boolean, default: false

  defp question_options_fields(assigns) do
    ~H"""
    <.inputs_for :let={option_form} field={@field}>
      <div class="flex items-center gap-2">
        <input
          :if={@include_position?}
          type="hidden"
          name={"#{option_form.name}[position]"}
          value={option_form.index + 1}
        />
        <input
          type="radio"
          name="question[correct_option_id]"
          value={option_form.index}
          checked={option_form[:correct].value == true}
          class="h-4 w-4 text-primary"
        />
        <div class="flex-1">
          <.input field={option_form[:label]} type="text" />
        </div>
      </div>
    </.inputs_for>
    <.field_error field={@field} />
    """
  end

  attr :status, :atom, required: true
  attr :generated_count, :integer, default: nil
  attr :remaining_count, :integer, default: 0

  defp generation_status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium",
      @status == :ready && @remaining_count > 0 && "bg-mint text-primary",
      @status == :ready && @remaining_count == 0 && "bg-soft text-body",
      @status == :failed && "bg-red-50 text-red-600",
      @status in [:pending, :processing] && "bg-soft text-body"
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

  defp draft_questions(quiz), do: Enum.filter(quiz.questions, &(&1.status == :draft))

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

  defp pluralize(1, unit), do: "1 #{unit}"
  defp pluralize(count, unit), do: "#{count} #{unit}s"

  defp draft_count_for_generation(quiz, generation_id) do
    Enum.count(quiz.questions, &(&1.status == :draft and &1.quiz_generation_id == generation_id))
  end

  defp option_letter(index), do: <<65 + index>>

  defp error_to_string(:too_large), do: "File is too large (max 25MB)."
  defp error_to_string(:not_accepted), do: "Only PDF files are accepted."
  defp error_to_string(:too_many_files), do: "Only one file at a time."
  defp error_to_string(other), do: to_string(other)
end
