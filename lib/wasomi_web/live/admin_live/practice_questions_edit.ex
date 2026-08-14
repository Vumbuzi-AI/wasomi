defmodule WasomiWeb.AdminLive.PracticeQuestionsEdit do
  use WasomiWeb, :live_view

  alias Wasomi.Assessments
  alias Wasomi.Assessments.PracticeQuestion
  alias Wasomi.Catalog

  @impl true
  def mount(%{"course_slug" => course_slug, "module_id" => module_id}, _session, socket) do
    course = Catalog.get_course_by_slug!(course_slug)
    module = load_module!(module_id, course)

    {:ok,
     socket
     |> assign(:page_title, "Practice questions · #{module.title}")
     |> assign(:course, course)
     |> assign(:module, module)
     |> assign(:new_practice_form, nil)
     |> assign(:deleting_question_id, nil)
     |> assign(:dirty_question_ids, MapSet.new())
     |> assign(:generating_ai?, false)
     |> reload_questions()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout current_user={@current_user}>
      <div class="mx-auto max-w-4xl space-y-8 px-4 py-8">
        <header class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <.link
              navigate={~p"/admin/courses/#{@course.slug}"}
              class="inline-flex items-center gap-1.5 text-sm font-medium text-muted hover:text-dark"
            >
              <.icon name="hero-arrow-left" class="h-4 w-4" /> {@course.title}
            </.link>
            <h1 class="mt-2 text-3xl font-semibold text-dark">
              Practice questions
            </h1>
            <p class="mt-1 text-body">
              {@module.title} · low-stakes drill, never counts toward completion or certificates
            </p>
          </div>
        </header>

        <section id="practice-questions-section" class="space-y-6">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div>
              <span class="text-sm font-semibold text-dark">
                {length(@practice_questions)} question{if length(@practice_questions) != 1,
                  do: "s"}
              </span>
              <span class="ml-2 text-sm text-muted">
                ({Enum.count(@practice_questions, &(&1.status == :published))} published)
              </span>
            </div>
            <div class="flex items-center gap-2">
              <button
                type="button"
                phx-click="generate_ai_practice_questions"
                disabled={@generating_ai?}
                class="inline-flex items-center gap-1.5 rounded-full border border-primary/30 bg-mint px-4 py-2 text-sm font-semibold text-primary transition hover:bg-mint/80 disabled:opacity-50 active:scale-[0.96]"
              >
                {if @generating_ai?, do: "Generating...", else: "Generate with AI"}
              </button>
              <button
                :if={is_nil(@new_practice_form)}
                type="button"
                phx-click="new_practice_question"
                class="rounded-full bg-dark px-4 py-2 text-sm font-semibold text-white transition hover:bg-primary active:scale-[0.96]"
              >
                Add question
              </button>
            </div>
          </div>

          <div
            :if={@practice_questions == [] && is_nil(@new_practice_form)}
            class="rounded-2xl border border-dashed border-black/10 p-10 text-center text-sm text-muted"
          >
            No practice questions yet. Add one to give learners extra drill material.
          </div>

          <div
            :for={question <- @practice_questions}
            class="rounded-3xl border border-black/5 bg-white p-6 lg:p-8 space-y-4"
          >
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0 flex-1">
                <span class={[
                  "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold",
                  if(question.status == :published,
                    do: "bg-mint text-primary",
                    else: "bg-amber-50 text-amber-700"
                  )
                ]}>
                  {if question.status == :published, do: "Published", else: "Draft"}
                </span>
                <p class="mt-2 text-sm font-medium text-dark">{question.prompt}</p>
                <ul class="mt-2 space-y-1">
                  <li
                    :for={opt <- question.practice_question_options}
                    class={[
                      "text-sm",
                      if(opt.correct, do: "font-semibold text-primary", else: "text-body")
                    ]}
                  >
                    {if opt.correct, do: "✓ ", else: "· "}{opt.label}
                  </li>
                </ul>
                <p :if={question.explanation} class="mt-2 text-xs text-muted italic">
                  {question.explanation}
                </p>
              </div>
              <div class="flex shrink-0 items-center gap-2">
                <button
                  :if={question.status == :draft}
                  type="button"
                  phx-click="publish_practice_question"
                  phx-value-id={question.id}
                  class="rounded-full border border-primary px-3 py-1.5 text-xs font-semibold text-primary transition hover:bg-mint active:scale-[0.96]"
                >
                  Publish
                </button>
                <button
                  type="button"
                  phx-click="confirm_delete_practice_question"
                  phx-value-id={question.id}
                  class="rounded-full border border-black/10 px-3 py-1.5 text-xs font-semibold text-muted transition hover:border-red-300 hover:text-red-600 active:scale-[0.96]"
                >
                  Remove
                </button>
              </div>
            </div>

            <div class="border-t border-black/5 pt-4">
              <.practice_question_form
                form={Map.fetch!(@practice_forms, question.id)}
                question={question}
                dirty={MapSet.member?(@dirty_question_ids, question.id)}
              />
            </div>
          </div>

          <section
            :if={@new_practice_form}
            class="rounded-3xl border border-primary/20 bg-white p-6 shadow-sm lg:p-8"
          >
            <h2 class="mb-5 font-semibold text-dark">New practice question</h2>
            <.practice_question_form form={@new_practice_form} question={nil} />
          </section>
        </section>
      </div>

      <.confirm_modal
        :if={@deleting_question_id}
        id="delete-practice-question-modal"
        title="Remove this practice question?"
        confirm_label="Remove"
        confirm={JS.push("delete_practice_question", value: %{id: @deleting_question_id})}
        cancel={JS.push("cancel_delete_practice_question")}
      >
        This can't be undone.
      </.confirm_modal>
    </.admin_layout>
    """
  end

  @impl true
  def handle_event("new_practice_question", _params, socket) do
    changeset =
      Assessments.change_practice_question(%PracticeQuestion{
        practice_question_options: blank_options()
      })

    {:noreply, assign(socket, :new_practice_form, to_form(changeset))}
  end

  @impl true
  def handle_event("cancel_new_practice_question", _params, socket) do
    {:noreply, assign(socket, :new_practice_form, nil)}
  end

  @impl true
  def handle_event(
        "validate_new_practice_question",
        %{"practice_question" => params} = full,
        socket
      ) do
    params = apply_correct_option(params, correct_option_id(full, "new-practice-question"))

    changeset =
      %PracticeQuestion{practice_question_options: blank_options()}
      |> Assessments.change_practice_question(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :new_practice_form, to_form(changeset))}
  end

  @impl true
  def handle_event(
        "save_new_practice_question",
        %{"practice_question" => params} = full,
        socket
      ) do
    params = apply_correct_option(params, correct_option_id(full, "new-practice-question"))

    case Assessments.create_practice_question(socket.assigns.module, params) do
      {:ok, _question} ->
        {:noreply,
         socket
         |> put_flash(:info, "Practice question added.")
         |> assign(:new_practice_form, nil)
         |> reload_questions()}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_practice_form, to_form(changeset, action: :insert))}
    end
  end

  @impl true
  def handle_event("add_practice_option", %{"id" => "new"}, socket) do
    changeset = socket.assigns.new_practice_form.source
    options = Ecto.Changeset.get_field(changeset, :practice_question_options, [])

    if length(options) < 4 do
      new_option = %Wasomi.Assessments.PracticeQuestionOption{
        label: "",
        correct: false,
        position: length(options) + 1
      }

      updated =
        changeset
        |> Ecto.Changeset.put_assoc(:practice_question_options, options ++ [new_option])
        |> Map.put(:action, :validate)

      {:noreply, assign(socket, :new_practice_form, to_form(updated))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_practice_option", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    question = find_question!(socket, id)
    form = Map.fetch!(socket.assigns.practice_forms, id)
    options = Ecto.Changeset.get_field(form.source, :practice_question_options, [])

    if length(options) < 4 do
      new_option = %Wasomi.Assessments.PracticeQuestionOption{
        label: "",
        correct: false,
        position: length(options) + 1
      }

      updated =
        form.source
        |> Ecto.Changeset.put_assoc(:practice_question_options, options ++ [new_option])
        |> Map.put(:action, :validate)

      forms = Map.put(socket.assigns.practice_forms, question.id, to_form(updated))
      {:noreply, socket |> assign(:practice_forms, forms) |> mark_dirty(question.id)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_practice_option", %{"id" => "new", "index" => index_str}, socket) do
    index = String.to_integer(index_str)
    changeset = socket.assigns.new_practice_form.source
    options = Ecto.Changeset.get_field(changeset, :practice_question_options, [])

    updated =
      changeset
      |> Ecto.Changeset.put_assoc(:practice_question_options, List.delete_at(options, index))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :new_practice_form, to_form(updated))}
  end

  @impl true
  def handle_event("remove_practice_option", %{"id" => id_str, "index" => index_str}, socket) do
    id = String.to_integer(id_str)
    question = find_question!(socket, id)
    form = Map.fetch!(socket.assigns.practice_forms, id)
    index = String.to_integer(index_str)
    options = Ecto.Changeset.get_field(form.source, :practice_question_options, [])

    updated =
      form.source
      |> Ecto.Changeset.put_assoc(:practice_question_options, List.delete_at(options, index))
      |> Map.put(:action, :validate)

    forms = Map.put(socket.assigns.practice_forms, question.id, to_form(updated))
    {:noreply, socket |> assign(:practice_forms, forms) |> mark_dirty(question.id)}
  end

  @impl true
  def handle_event(
        "validate_practice_question",
        %{"id" => id_str, "practice_question" => params} = full,
        socket
      ) do
    id = String.to_integer(id_str)
    question = find_question!(socket, id)
    params = apply_correct_option(params, correct_option_id(full, "practice-question-#{id}"))

    changeset =
      question
      |> Assessments.change_practice_question(params)
      |> Map.put(:action, :validate)

    forms = Map.put(socket.assigns.practice_forms, question.id, to_form(changeset))

    {:noreply,
     socket
     |> assign(:practice_forms, forms)
     |> mark_dirty(question.id)}
  end

  @impl true
  def handle_event(
        "save_practice_question",
        %{"id" => id_str, "practice_question" => params} = full,
        socket
      ) do
    id = String.to_integer(id_str)
    question = find_question!(socket, id)
    params = apply_correct_option(params, correct_option_id(full, "practice-question-#{id}"))

    case Assessments.update_practice_question(question, params) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Practice question saved.")
         |> reload_questions()
         |> then(fn s ->
           assign(s, :dirty_question_ids, MapSet.delete(s.assigns.dirty_question_ids, id))
         end)}

      {:error, changeset} ->
        forms =
          Map.put(socket.assigns.practice_forms, question.id, to_form(changeset, action: :insert))

        {:noreply, assign(socket, :practice_forms, forms)}
    end
  end

  @impl true
  def handle_event("publish_practice_question", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    question = find_question!(socket, id)

    case Assessments.publish_practice_question(question) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Practice question published.")
         |> reload_questions()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not publish practice question.")}
    end
  end

  @impl true
  def handle_event("confirm_delete_practice_question", %{"id" => id_val}, socket) do
    {:noreply, assign(socket, :deleting_question_id, to_string(id_val) |> String.to_integer())}
  end

  @impl true
  def handle_event("cancel_delete_practice_question", _params, socket) do
    {:noreply, assign(socket, :deleting_question_id, nil)}
  end

  @impl true
  def handle_event("delete_practice_question", %{"id" => id_val}, socket) do
    id = to_string(id_val) |> String.to_integer()
    question = find_question!(socket, id)
    {:ok, _} = Assessments.delete_practice_question(question)

    {:noreply,
     socket
     |> put_flash(:info, "Practice question removed.")
     |> assign(:deleting_question_id, nil)
     |> reload_questions()}
  end

  @impl true
  def handle_event("generate_ai_practice_questions", _params, socket) do
    if socket.assigns.generating_ai? do
      {:noreply, socket}
    else
      module = socket.assigns.module

      {:noreply,
       socket
       |> assign(:generating_ai?, true)
       |> start_async({:generate_ai_practice_questions, module.id}, fn ->
         Assessments.generate_practice_questions_for_module(module, count: 5)
       end)}
    end
  end

  @impl true
  def handle_async(
        {:generate_ai_practice_questions, _module_id},
        {:ok, {:ok, questions}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:generating_ai?, false)
     |> put_flash(:info, "Generated #{length(questions)} AI practice questions!")
     |> reload_questions()}
  end

  @impl true
  def handle_async(
        {:generate_ai_practice_questions, _module_id},
        {:ok, {:error, _reason}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:generating_ai?, false)
     |> put_flash(:error, "Could not generate practice questions at this time.")}
  end

  @impl true
  def handle_async(
        {:generate_ai_practice_questions, _module_id},
        {:exit, _reason},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:generating_ai?, false)
     |> put_flash(:error, "Practice question generation timed out.")}
  end

  defp reload_questions(socket) do
    questions = Assessments.list_all_practice_questions(socket.assigns.module)

    forms =
      Map.new(questions, fn q ->
        {q.id, to_form(Assessments.change_practice_question(q))}
      end)

    socket
    |> assign(:practice_questions, questions)
    |> assign(:practice_forms, forms)
  end

  defp load_module!(module_id, course) do
    module = Wasomi.Repo.get!(Wasomi.Catalog.CourseModule, module_id)

    if module.course_id == course.id do
      module
    else
      raise Ecto.NoResultsError, queryable: Wasomi.Catalog.CourseModule
    end
  end

  defp find_question!(socket, id) do
    Enum.find(socket.assigns.practice_questions, &(&1.id == id)) ||
      raise Ecto.NoResultsError, queryable: PracticeQuestion
  end

  defp mark_dirty(socket, question_id) do
    assign(
      socket,
      :dirty_question_ids,
      MapSet.put(socket.assigns.dirty_question_ids, question_id)
    )
  end

  defp blank_options do
    Enum.map(
      1..4,
      &%Wasomi.Assessments.PracticeQuestionOption{
        label: "",
        correct: false,
        position: &1
      }
    )
  end

  defp correct_option_id(full_params, prefix),
    do: get_in(full_params, [prefix, "correct_option_id"])

  defp apply_correct_option(params, nil), do: params
  defp apply_correct_option(params, ""), do: params

  defp apply_correct_option(params, correct_option_id) do
    correct_index = to_string(correct_option_id)

    Map.update(params, "practice_question_options", %{}, fn options ->
      Map.new(options, fn {index, option_attrs} ->
        {index, Map.put(option_attrs, "correct", index == correct_index)}
      end)
    end)
  end
end
