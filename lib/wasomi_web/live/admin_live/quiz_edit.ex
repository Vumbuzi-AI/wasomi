defmodule WasomiWeb.AdminLive.QuizEdit do
  use WasomiWeb, :live_view

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Question

  @impl true
  def mount(%{"course_id" => course_id, "id" => quiz_id}, _session, socket) do
    quiz = load_quiz!(quiz_id, course_id)

    {:ok,
     socket
     |> assign(:page_title, "Edit quiz")
     |> assign(:course_id, course_id)
     |> assign(:publish_errors, [])
     |> assign(:new_question_form, nil)
     |> assign_quiz(quiz)}
  end

  @impl true
  def handle_event("validate_question", %{"id" => id, "question" => params}, socket) do
    question = find_question!(socket.assigns.quiz, id)

    changeset =
      question
      |> Assessments.change_question(apply_correct_option(params))
      |> Map.put(:action, :validate)

    forms = Map.put(socket.assigns.question_forms, question.id, to_form(changeset))
    {:noreply, assign(socket, :question_forms, forms)}
  end

  def handle_event("validate_new_question", %{"question" => params}, socket) do
    changeset =
      %Question{quiz_id: socket.assigns.quiz.id}
      |> Assessments.change_question(apply_correct_option(params))
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
      {:noreply, assign(socket, :question_forms, forms)}
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
      {:noreply, assign(socket, :question_forms, forms)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_question", %{"id" => id, "question" => params}, socket) do
    question = find_question!(socket.assigns.quiz, id)

    case Assessments.update_question(question, apply_correct_option(params)) do
      {:ok, _question} ->
        {:noreply,
         socket
         |> put_flash(:info, "Question saved.")
         |> assign(:publish_errors, [])
         |> reload_quiz()}

      {:error, changeset} ->
        forms =
          Map.put(socket.assigns.question_forms, question.id, to_form(changeset, action: :insert))

        {:noreply, assign(socket, :question_forms, forms)}
    end
  end

  def handle_event("new_question", _params, socket) do
    changeset =
      Assessments.change_question(%Question{quiz_id: socket.assigns.quiz.id}, %{
        position: next_position(socket.assigns.quiz),
        status: :draft,
        question_options: blank_options()
      })

    {:noreply, assign(socket, :new_question_form, to_form(changeset))}
  end

  def handle_event("cancel_new_question", _params, socket) do
    {:noreply, assign(socket, :new_question_form, nil)}
  end

  def handle_event("save_new_question", %{"question" => params}, socket) do
    params =
      params
      |> apply_correct_option()
      |> Map.put("position", to_string(next_position(socket.assigns.quiz)))
      |> Map.put("status", "draft")

    case Assessments.create_question(socket.assigns.quiz, params) do
      {:ok, _question} ->
        {:noreply,
         socket
         |> put_flash(:info, "Question added.")
         |> assign(:new_question_form, nil)
         |> assign(:publish_errors, [])
         |> reload_quiz()}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_question_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("delete_question", %{"id" => id}, socket) do
    question = find_question!(socket.assigns.quiz, id)
    {:ok, _question} = Assessments.delete_question(question)

    {:noreply,
     socket
     |> put_flash(:info, "Question removed.")
     |> assign(:publish_errors, [])
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
            navigate={~p"/admin/courses/#{@course_id}/quizzes/#{@quiz.id}"}
            class="inline-flex items-center gap-1.5 text-sm font-medium text-muted hover:text-primary"
          >
            <.icon name="hero-arrow-left-mini" class="h-4 w-4" /> Back to quiz management
          </.link>
          <span
            id="quiz-status"
            class={[
              "rounded-full px-3 py-1 text-xs font-semibold",
              @quiz.active && "bg-mint text-primary",
              !@quiz.active && "bg-soft text-body"
            ]}
          >
            {if @quiz.active, do: "Active", else: "Draft"}
          </span>
        </div>

        <header>
          <p class="text-sm font-semibold uppercase tracking-wider text-primary">Quiz editor</p>
          <h1 class="mt-2 text-3xl font-semibold text-dark">{@quiz.title}</h1>
          <p class="mt-2 text-body">
            Edit every question inline, drag questions into order, then publish when the quiz is complete.
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
            class="rounded-3xl border border-black/5 bg-white p-6 shadow-sm data-[dragging=true]:opacity-50 lg:p-8"
          >
            <div class="mb-5 flex items-center justify-between gap-4">
              <div class="flex items-center gap-3">
                <button
                  type="button"
                  data-sortable-handle
                  title="Drag to reorder"
                  class="cursor-grab rounded-lg p-2 text-muted hover:bg-soft hover:text-dark active:cursor-grabbing"
                >
                  <.icon name="hero-bars-3" class="h-5 w-5" />
                </button>
                <h2 class="font-semibold text-dark">Question {index}</h2>
              </div>
              <button
                type="button"
                phx-click="delete_question"
                phx-value-id={question.id}
                data-confirm="Remove this question?"
                class="inline-flex items-center gap-1.5 text-sm font-medium text-red-500 hover:text-red-700"
              >
                <.icon name="hero-trash" class="h-4 w-4" /> Remove
              </button>
            </div>

            <.question_form form={Map.fetch!(@question_forms, question.id)} question={question} />
          </article>
        </div>

        <section
          :if={@quiz.questions == [] && is_nil(@new_question_form)}
          id="empty-quiz"
          class="rounded-3xl border border-dashed border-black/10 bg-white p-10 text-center"
        >
          <p class="font-medium text-dark">This quiz has no questions yet.</p>
          <p class="mt-1 text-sm text-body">Add the first question before publishing.</p>
        </section>

        <section
          :if={@new_question_form}
          id="new-question"
          class="rounded-3xl border border-primary/20 bg-white p-6 lg:p-8"
        >
          <h2 class="mb-5 font-semibold text-dark">New question</h2>
          <.question_form form={@new_question_form} question={nil} />
        </section>

        <div class="flex flex-wrap items-center justify-between gap-4 rounded-3xl bg-dark p-6 text-white">
          <button
            :if={is_nil(@new_question_form)}
            id="add-question"
            type="button"
            phx-click="new_question"
            class="inline-flex items-center gap-2 rounded-full border border-white/20 px-5 py-2.5 text-sm font-semibold hover:bg-white hover:text-dark"
          >
            <.icon name="hero-plus" class="h-4 w-4" /> Add question
          </button>
          <span :if={@new_question_form} class="text-sm text-white/60">
            Save or cancel the new question before publishing.
          </span>
          <button
            id="publish-quiz"
            type="button"
            phx-click="publish"
            disabled={!is_nil(@new_question_form)}
            class="ml-auto inline-flex items-center gap-2 rounded-full bg-primary px-6 py-3 font-semibold text-white transition hover:bg-white hover:text-dark disabled:cursor-not-allowed disabled:opacity-40"
          >
            <.icon name="hero-paper-airplane" class="h-5 w-5" />
            {if @quiz.active, do: "Publish updates", else: "Publish quiz"}
          </button>
        </div>
      </div>
    </.admin_layout>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :question, :any, required: true

  defp question_form(assigns) do
    assigns =
      assign(
        assigns,
        :input_prefix,
        if(assigns.question, do: "question-#{assigns.question.id}", else: "new-question")
      )

    ~H"""
    <.form
      for={@form}
      id={if @question, do: "question-form-#{@question.id}", else: "new-question-form"}
      phx-change={if @question, do: "validate_question", else: "validate_new_question"}
      phx-submit={if @question, do: "save_question", else: "save_new_question"}
      phx-value-id={@question && @question.id}
      class="space-y-5"
    >
      <.input
        field={@form[:prompt]}
        id={"#{@input_prefix}-prompt"}
        type="textarea"
        label="Question text"
      />
      <.input
        field={@form[:explanation]}
        id={"#{@input_prefix}-explanation"}
        type="textarea"
        label="Explanation"
        placeholder="Explain why the selected answer is correct"
      />

      <fieldset>
        <legend class="mb-3 text-sm font-semibold text-dark">
          Answer options <span class="font-normal text-body">(select the correct answer)</span>
        </legend>
        <div class="space-y-3">
          <.inputs_for :let={option_form} field={@form[:question_options]}>
            <div class="flex items-start gap-3">
              <input
                type="radio"
                name="question[correct_option_id]"
                value={option_form.index}
                checked={option_form[:correct].value == true}
                aria-label={"Mark option #{option_form.index + 1} correct"}
                class="mt-3 h-4 w-4 border-black/20 text-primary focus:ring-primary"
              />
              <input
                type="hidden"
                name={"#{option_form.name}[position]"}
                value={option_form.index + 1}
              />
              <div class="flex-1">
                <.input
                  field={option_form[:label]}
                  id={"#{@input_prefix}-option-#{option_form.index}"}
                  type="text"
                  label={"Option #{option_form.index + 1}"}
                />
              </div>
              <button
                :if={length(@form.impl.to_form(@form.source, @form, :question_options, [])) > 2}
                type="button"
                phx-click="remove_option"
                phx-value-id={if @question, do: @question.id, else: "new"}
                phx-value-index={option_form.index}
                tabindex="-1"
                class="mt-8 p-2 text-muted hover:text-red-500 rounded-lg hover:bg-soft transition shrink-0"
                title="Remove option"
              >
                <.icon name="hero-trash" class="h-4 w-4" />
              </button>
            </div>
          </.inputs_for>
          <div
            :if={length(@form.impl.to_form(@form.source, @form, :question_options, [])) < 4}
            class="pt-1"
          >
            <button
              type="button"
              phx-click="add_option"
              phx-value-id={if @question, do: @question.id, else: "new"}
              class="inline-flex items-center gap-1.5 rounded-full border border-black/10 px-3 py-1.5 text-xs font-semibold text-dark transition hover:bg-soft hover:text-primary"
            >
              <.icon name="hero-plus-circle" class="h-4 w-4" /> Add option
            </button>
          </div>
          <.field_error field={@form[:question_options]} />
        </div>
      </fieldset>

      <div class="flex items-center gap-4">
        <button
          type="submit"
          class="rounded-full bg-dark px-5 py-2.5 text-sm font-semibold text-white hover:bg-primary"
        >
          {if @question, do: "Save question", else: "Add question"}
        </button>
        <button
          :if={is_nil(@question)}
          type="button"
          phx-click="cancel_new_question"
          class="text-sm font-medium text-muted hover:text-dark"
        >
          Cancel
        </button>
      </div>
    </.form>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp field_error(assigns) do
    ~H"""
    <.error :for={error <- @field.errors}>{translate_error(error)}</.error>
    """
  end

  defp load_quiz!(quiz_id, course_id) do
    quiz = Assessments.get_quiz_with_questions!(quiz_id)

    if to_string(quiz.module.course_id) == to_string(course_id) do
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

    socket
    |> assign(:quiz, quiz)
    |> assign(:question_forms, forms)
  end

  defp reload_quiz(socket) do
    quiz = load_quiz!(socket.assigns.quiz.id, socket.assigns.course_id)
    assign_quiz(socket, quiz)
  end

  defp find_question!(quiz, id) do
    Enum.find(quiz.questions, &(to_string(&1.id) == to_string(id))) ||
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

  defp blank_options do
    Enum.map(1..4, &%{label: "", correct: false, position: &1})
  end

  defp next_position(quiz) do
    quiz.questions
    |> Enum.map(& &1.position)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end
end
