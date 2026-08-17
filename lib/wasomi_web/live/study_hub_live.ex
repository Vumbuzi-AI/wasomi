defmodule WasomiWeb.StudyHubLive do
  @moduledoc """
  Cross-course self-study destination: Flashcards, Extra practice, and
  Timed quiz, scoped to any module (or a single lecture within it) across
  every course the learner is actively enrolled in.

  Unlike `CoursePlayerLive`, there is no preview mode here — this is a pure
  learner destination, so every rating/answer/submission is always
  persisted for the current user; there's no in-memory-only branch to
  maintain.

  State is URL-driven (`push_patch`/`handle_params`) rather than
  assign-only, on purpose: a course+module(+lecture)+mode combination is
  meant to be bookmarkable and shareable — the deep-link entry points on
  a course page land here pre-scoped.
  """

  use WasomiWeb, :live_view

  import WasomiWeb.StudyComponents

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Workers.GenerateFlashcardsWorker
  alias Wasomi.Assessments.Workers.GeneratePracticeSetQuestionsWorker
  alias Wasomi.Catalog.CourseModule
  alias Wasomi.Catalog.Lecture
  alias Wasomi.Enrollments

  @impl true
  def mount(_params, _session, socket) do
    enrollments = Enrollments.list_active_for_user(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Study")
     |> assign(:enrollments, enrollments)
     |> assign(:loaded_key, nil)
     |> assign(:flashcard_set, nil)
     |> assign(:flashcard_cards, [])
     |> assign(:flashcard_index, 0)
     |> assign(:flashcard_flipped?, false)
     |> assign(:practice_set, nil)
     |> assign(:practice_set_questions, [])
     |> assign(:practice_answers, %{})
     |> assign(:practice_index, 0)
     |> assign(:timed_quiz_target, nil)
     |> assign(:timed_quiz_time_limit_seconds, nil)
     |> assign(:timed_current_quiz, nil)
     |> assign(:timed_quiz_answers, %{})
     |> assign(:timed_current_question_index, 0)
     |> assign(:timed_quiz_result, nil)
     |> assign(:timed_quiz_time_expired?, false)
     |> assign(:timed_quiz_deadline, nil)
     |> assign(:timed_quiz_timer_ref, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket |> resolve_scope_and_mode(params) |> maybe_load_content()}
  end

  defp resolve_scope_and_mode(socket, params) do
    course = resolve_course(socket.assigns.enrollments, params)
    module = resolve_module(course, params)
    scope = resolve_scope_selection(module, params)
    mode = resolve_mode(scope, params)

    socket
    |> assign(:selected_course, course)
    |> assign(:selected_module, module)
    |> assign(:scope, scope)
    |> assign(:mode, mode)
    |> assign(:step, compute_step(course, module, scope, mode))
  end

  defp resolve_course(enrollments, %{"course" => slug}) do
    Enum.find_value(enrollments, fn e -> if e.course.slug == slug, do: e.course end)
  end

  defp resolve_course(enrollments, _params) do
    case enrollments do
      [%{course: course}] -> course
      _otherwise -> nil
    end
  end

  defp resolve_module(nil, _params), do: nil

  defp resolve_module(course, %{"module" => id}) do
    Enum.find(course.modules, &(to_string(&1.id) == id))
  end

  defp resolve_module(course, _params) do
    case course.modules do
      [module] -> module
      _otherwise -> nil
    end
  end

  defp resolve_scope_selection(nil, _params), do: nil
  defp resolve_scope_selection(module, %{"scope" => "module"}), do: module

  defp resolve_scope_selection(module, %{"scope" => "lecture", "lecture" => id}) do
    Enum.find(module.lectures, &(to_string(&1.id) == id))
  end

  defp resolve_scope_selection(_module, _params), do: nil

  defp resolve_mode(%CourseModule{}, %{"mode" => "timed_quiz"}), do: :timed_quiz
  defp resolve_mode(_scope, %{"mode" => "flashcards"}), do: :flashcards
  defp resolve_mode(_scope, %{"mode" => "practice"}), do: :practice
  defp resolve_mode(_scope, _params), do: nil

  defp compute_step(nil, _module, _scope, _mode), do: :course
  defp compute_step(_course, nil, _scope, _mode), do: :module
  defp compute_step(_course, _module, nil, _mode), do: :scope
  defp compute_step(_course, _module, _scope, nil), do: :mode
  defp compute_step(_course, _module, _scope, _mode), do: :content

  # Loading (and, for Flashcards/Practice, first-visit generation + PubSub
  # subscribe) only happens once per distinct (scope, mode) combination —
  # `handle_params` can otherwise re-fire without the scope/mode actually
  # changing, and re-running this would both double-subscribe (no unsubscribe
  # API exists in this app, so duplicate subscriptions would double-deliver
  # broadcasts) and blow away an in-progress timed-quiz attempt.
  defp maybe_load_content(socket) do
    key = {scope_key(socket.assigns.scope), socket.assigns.mode}

    if socket.assigns.step == :content and socket.assigns.loaded_key != key do
      socket
      |> assign(:loaded_key, key)
      |> load_content()
    else
      socket
    end
  end

  defp scope_key(%CourseModule{id: id}), do: {:module, id}
  defp scope_key(%Lecture{id: id}), do: {:lecture, id}
  defp scope_key(nil), do: nil

  defp load_content(%{assigns: %{mode: :flashcards, scope: scope}} = socket) do
    {:ok, set} = Assessments.get_or_create_flashcard_set(scope)
    maybe_enqueue_flashcard_generation(set)
    Assessments.subscribe_to_flashcard_set(scope)
    load_flashcard_cards(socket, set)
  end

  defp load_content(%{assigns: %{mode: :practice, scope: scope}} = socket) do
    {:ok, quiz} = Assessments.get_or_create_practice_set(scope)
    maybe_enqueue_practice_generation(quiz)
    Assessments.subscribe_to_practice_set(scope)
    load_practice_set_questions(socket, quiz)
  end

  defp load_content(%{assigns: %{mode: :timed_quiz, scope: %CourseModule{} = module}} = socket) do
    quiz = Assessments.get_quiz_for_module(module)
    question_count = if quiz, do: length(Assessments.list_published_questions(quiz)), else: 0

    socket
    |> assign(:timed_quiz_target, %{module: module, quiz: quiz, question_count: question_count})
    |> reset_timed_quiz_attempt()
  end

  defp maybe_enqueue_flashcard_generation(%{status: :pending} = set),
    do: GenerateFlashcardsWorker.enqueue(set.id)

  defp maybe_enqueue_flashcard_generation(_set), do: :ok

  defp maybe_enqueue_practice_generation(%{status: :pending} = quiz),
    do: GeneratePracticeSetQuestionsWorker.enqueue(quiz.id)

  defp maybe_enqueue_practice_generation(_quiz), do: :ok

  ## Picker navigation

  @impl true
  def handle_event("select-course", %{"slug" => slug}, socket) do
    {:noreply, push_patch(socket, to: ~p"/learn/study?#{%{course: slug}}")}
  end

  @impl true
  def handle_event("select-module", %{"module_id" => module_id}, socket) do
    course = socket.assigns.selected_course

    {:noreply,
     push_patch(socket, to: ~p"/learn/study?#{%{course: course.slug, module: module_id}}")}
  end

  @impl true
  def handle_event("select-scope", %{"scope" => "module"}, socket) do
    %{selected_course: course, selected_module: module} = socket.assigns

    {:noreply,
     push_patch(socket,
       to: ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module"}}"
     )}
  end

  @impl true
  def handle_event("select-scope", %{"scope" => "lecture", "lecture_id" => lecture_id}, socket) do
    %{selected_course: course, selected_module: module} = socket.assigns

    {:noreply,
     push_patch(socket,
       to:
         ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "lecture", lecture: lecture_id}}"
     )}
  end

  @impl true
  def handle_event("select-mode", %{"mode" => mode}, socket) do
    params = Map.put(scope_params(socket.assigns), :mode, mode)
    {:noreply, push_patch(socket, to: ~p"/learn/study?#{params}")}
  end

  @impl true
  def handle_event("change-course", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/learn/study")}
  end

  @impl true
  def handle_event("change-module", _params, socket) do
    course = socket.assigns.selected_course
    {:noreply, push_patch(socket, to: ~p"/learn/study?#{%{course: course.slug}}")}
  end

  @impl true
  def handle_event("change-scope", _params, socket) do
    %{selected_course: course, selected_module: module} = socket.assigns

    {:noreply,
     push_patch(socket, to: ~p"/learn/study?#{%{course: course.slug, module: module.id}}")}
  end

  @impl true
  def handle_event("change-mode", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/learn/study?#{scope_params(socket.assigns)}")}
  end

  ## Flashcards

  @impl true
  def handle_event("retry-flashcard-generation", _params, socket) do
    case socket.assigns.flashcard_set do
      %{status: :failed} = set -> GenerateFlashcardsWorker.enqueue(set.id)
      _set -> :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("flip-flashcard", _params, socket) do
    {:noreply, update(socket, :flashcard_flipped?, &(!&1))}
  end

  @impl true
  def handle_event("flashcard-next", _params, socket) do
    {:noreply, advance_flashcard(socket)}
  end

  @impl true
  def handle_event("flashcard-prev", _params, socket) do
    {:noreply,
     socket
     |> assign(:flashcard_index, max(socket.assigns.flashcard_index - 1, 0))
     |> assign(:flashcard_flipped?, false)}
  end

  @impl true
  def handle_event("rate-flashcard", %{"rating" => rating_str}, socket) do
    rating = safe_flashcard_rating(rating_str)
    current = Enum.at(socket.assigns.flashcard_cards, socket.assigns.flashcard_index)

    case {rating, current} do
      {nil, _} ->
        {:noreply, socket}

      {_rating, nil} ->
        {:noreply, socket}

      {rating, %{flashcard: flashcard}} ->
        {:noreply, socket |> rate_flashcard(flashcard, rating) |> advance_flashcard()}
    end
  end

  @impl true
  def handle_event("restart-flashcard-deck", _params, socket) do
    {:noreply, load_flashcard_cards(socket, socket.assigns.flashcard_set)}
  end

  @impl true
  def handle_event("review-unknown-flashcards", _params, socket) do
    unknown =
      Enum.filter(socket.assigns.flashcard_cards, fn %{progress: progress} ->
        is_nil(progress) or progress.status != :known
      end)

    cards = if unknown == [], do: socket.assigns.flashcard_cards, else: unknown

    {:noreply,
     socket
     |> assign(:flashcard_cards, cards)
     |> assign(:flashcard_index, 0)
     |> assign(:flashcard_flipped?, false)}
  end

  ## Extra practice

  @impl true
  def handle_event("retry-practice-generation", _params, socket) do
    case socket.assigns.practice_set do
      %{status: :failed} = quiz -> GeneratePracticeSetQuestionsWorker.enqueue(quiz.id)
      _quiz -> :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "select-practice-option",
        %{"question-id" => question_id_str, "option-id" => option_id_str},
        socket
      ) do
    question =
      Enum.find(socket.assigns.practice_set_questions, &(to_string(&1.id) == question_id_str))

    if question && not Map.has_key?(socket.assigns.practice_answers, question.id) do
      {:noreply, answer_practice_set_question(socket, question, option_id_str)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("practice-next", _params, socket) do
    last_index = length(socket.assigns.practice_set_questions)
    next_index = min(socket.assigns.practice_index + 1, last_index)
    {:noreply, assign(socket, :practice_index, next_index)}
  end

  @impl true
  def handle_event("practice-prev", _params, socket) do
    prev_index = max(socket.assigns.practice_index - 1, 0)
    {:noreply, assign(socket, :practice_index, prev_index)}
  end

  @impl true
  def handle_event("restart-practice-set", _params, socket) do
    {:noreply,
     socket
     |> assign(:practice_answers, %{})
     |> assign(:practice_index, 0)}
  end

  ## Timed quiz — always the real module Quiz/QuizSubmission, deliberately
  ## without the course page's `module_quiz_unlocked?` gate: this is pure
  ## self-study, consistent with Flashcards/Practice being ungated
  ## everywhere, and dropping the gate here has no progression or
  ## certificate consequence (neither reads module-level QuizSubmissions).

  @impl true
  def handle_event("start-timed-quiz", %{"seconds-per-question" => seconds_str}, socket) do
    with {seconds_per_question, ""} <- Integer.parse(seconds_str),
         true <- seconds_per_question > 0,
         %{module: module, quiz: quiz} when not is_nil(quiz) <- socket.assigns.timed_quiz_target,
         questions when questions != [] <- Assessments.list_published_questions(quiz) do
      {:noreply, start_timed_quiz(socket, module, quiz, questions, seconds_per_question)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "select-timed-quiz-option",
        %{"question-id" => q_id, "option-id" => opt_id},
        socket
      ) do
    answers = Map.put(socket.assigns.timed_quiz_answers, to_string(q_id), to_string(opt_id))
    {:noreply, assign(socket, :timed_quiz_answers, answers)}
  end

  @impl true
  def handle_event("timed-quiz-next", _params, socket) do
    last_index = length(socket.assigns.timed_current_quiz.questions) - 1
    next_index = min(socket.assigns.timed_current_question_index + 1, last_index)
    {:noreply, assign(socket, :timed_current_question_index, next_index)}
  end

  @impl true
  def handle_event("timed-quiz-prev", _params, socket) do
    prev_index = max(socket.assigns.timed_current_question_index - 1, 0)
    {:noreply, assign(socket, :timed_current_question_index, prev_index)}
  end

  @impl true
  def handle_event("submit-timed-quiz", _params, socket) do
    {:noreply, socket |> cancel_timed_quiz_timer() |> score_timed_quiz(false)}
  end

  @impl true
  def handle_event("retake-timed-quiz", _params, socket) do
    %{module: module, quiz: quiz, questions: questions} = socket.assigns.timed_current_quiz
    seconds_per_question = socket.assigns.timed_quiz_time_limit_seconds

    {:noreply, start_timed_quiz(socket, module, quiz, questions, seconds_per_question)}
  end

  defp scope_params(%{selected_course: course, selected_module: module, scope: %Lecture{} = l}) do
    %{course: course.slug, module: module.id, scope: "lecture", lecture: l.id}
  end

  defp scope_params(%{selected_course: course, selected_module: module, scope: %CourseModule{}}) do
    %{course: course.slug, module: module.id, scope: "module"}
  end

  defp load_flashcard_cards(socket, set) do
    cards =
      set
      |> Assessments.list_flashcards_with_progress(socket.assigns.current_user)
      |> Enum.map(fn {flashcard, progress} -> %{flashcard: flashcard, progress: progress} end)

    socket
    |> assign(:flashcard_set, set)
    |> assign(:flashcard_cards, cards)
    |> assign(:flashcard_index, 0)
    |> assign(:flashcard_flipped?, false)
  end

  defp rate_flashcard(socket, flashcard, rating) do
    {:ok, progress} =
      Assessments.record_flashcard_progress(socket.assigns.current_user, flashcard, rating)

    update(socket, :flashcard_cards, fn cards ->
      Enum.map(cards, fn
        %{flashcard: %{id: id}} = entry when id == flashcard.id -> %{entry | progress: progress}
        entry -> entry
      end)
    end)
  end

  defp advance_flashcard(socket) do
    max_index = length(socket.assigns.flashcard_cards)

    socket
    |> assign(:flashcard_index, min(socket.assigns.flashcard_index + 1, max_index))
    |> assign(:flashcard_flipped?, false)
  end

  defp safe_flashcard_rating("known"), do: :known
  defp safe_flashcard_rating("review_again"), do: :review_again
  defp safe_flashcard_rating(_other), do: nil

  defp load_practice_set_questions(socket, quiz) do
    questions = Assessments.list_practice_set_questions(quiz)

    socket
    |> assign(:practice_set, quiz)
    |> assign(:practice_set_questions, questions)
    |> assign(:practice_answers, %{})
    |> assign(:practice_index, 0)
  end

  defp answer_practice_set_question(socket, question, option_id_str) do
    correct? = Assessments.practice_answer_correct?(question, option_id_str)

    {:ok, _progress} =
      Assessments.record_practice_answer(socket.assigns.current_user, question, correct?)

    update(socket, :practice_answers, &Map.put(&1, question.id, option_id_str))
  end

  defp start_timed_quiz(socket, module, quiz, questions, seconds_per_question) do
    total_seconds = length(questions) * seconds_per_question
    deadline = DateTime.add(DateTime.utc_now(), total_seconds, :second)
    timer_ref = Process.send_after(self(), :timed_quiz_expired, total_seconds * 1000)

    socket
    |> assign(:timed_current_quiz, %{quiz: quiz, module: module, questions: questions})
    |> assign(:timed_quiz_time_limit_seconds, seconds_per_question)
    |> assign(:timed_quiz_answers, %{})
    |> assign(:timed_current_question_index, 0)
    |> assign(:timed_quiz_result, nil)
    |> assign(:timed_quiz_time_expired?, false)
    |> assign(:timed_quiz_deadline, deadline)
    |> assign(:timed_quiz_timer_ref, timer_ref)
  end

  defp reset_timed_quiz_attempt(socket) do
    socket
    |> assign(:timed_quiz_time_limit_seconds, nil)
    |> assign(:timed_current_quiz, nil)
    |> assign(:timed_quiz_answers, %{})
    |> assign(:timed_current_question_index, 0)
    |> assign(:timed_quiz_result, nil)
    |> assign(:timed_quiz_time_expired?, false)
    |> assign(:timed_quiz_deadline, nil)
    |> assign(:timed_quiz_timer_ref, nil)
  end

  defp cancel_timed_quiz_timer(socket) do
    case socket.assigns.timed_quiz_timer_ref do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end

    assign(socket, :timed_quiz_timer_ref, nil)
  end

  defp score_timed_quiz(socket, time_expired?) do
    %{quiz: quiz} = socket.assigns.timed_current_quiz
    answers = socket.assigns.timed_quiz_answers

    case Assessments.submit_quiz(socket.assigns.current_user, quiz, answers) do
      {:ok, submission} ->
        socket
        |> assign(:timed_quiz_result, submission)
        |> assign(:timed_quiz_time_expired?, time_expired?)

      {:error, _reason} ->
        socket
    end
  end

  ## Live updates

  @impl true
  def handle_info({:flashcard_set_updated, set}, socket) do
    if matches_scope?(socket.assigns.scope, set.module_id, set.lecture_id) do
      {:noreply, load_flashcard_cards(socket, set)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:practice_set_updated, quiz}, socket) do
    if matches_scope?(socket.assigns.scope, quiz.module_id, quiz.lecture_id) do
      {:noreply, load_practice_set_questions(socket, quiz)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:timed_quiz_expired, socket) do
    if socket.assigns.timed_current_quiz && !socket.assigns.timed_quiz_result do
      {:noreply,
       socket
       |> assign(:timed_quiz_timer_ref, nil)
       |> score_timed_quiz(true)}
    else
      {:noreply, socket}
    end
  end

  defp matches_scope?(%CourseModule{id: id}, module_id, _lecture_id), do: id == module_id
  defp matches_scope?(%Lecture{id: id}, _module_id, lecture_id), do: id == lecture_id
  defp matches_scope?(nil, _module_id, _lecture_id), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <.student_layout active={:study} current_user={@current_user}>
      <div class="mx-auto max-w-container px-5 py-8 lg:px-8 lg:py-12">
        <h1 class="text-3xl font-semibold tracking-tight text-ink sm:text-4xl">Study</h1>
        <p class="mt-2 text-body">
          Flashcards, extra practice, and timed quizzes — generated from your course
          materials, across everything you're enrolled in.
        </p>

        <div class="mt-8 overflow-hidden rounded-3xl border border-black/5 bg-white">
          <%= case @step do %>
            <% :course -> %>
              <.course_picker enrollments={@enrollments} />
            <% :module -> %>
              <.module_picker course={@selected_course} />
            <% :scope -> %>
              <.scope_picker course={@selected_course} module={@selected_module} />
            <% :mode -> %>
              <.mode_picker course={@selected_course} module={@selected_module} scope={@scope} />
            <% :content -> %>
              <.content_breadcrumb
                course={@selected_course}
                module={@selected_module}
                scope={@scope}
                mode={@mode}
              />
              <%= case @mode do %>
                <% :flashcards -> %>
                  <.flashcard_set_panel
                    flashcard_set={@flashcard_set}
                    flashcard_cards={@flashcard_cards}
                    flashcard_index={@flashcard_index}
                    flashcard_flipped?={@flashcard_flipped?}
                  />
                <% :practice -> %>
                  <.practice_set_panel
                    practice_set={@practice_set}
                    practice_set_questions={@practice_set_questions}
                    practice_answers={@practice_answers}
                    practice_index={@practice_index}
                  />
                <% :timed_quiz -> %>
                  <.timed_quiz_content
                    target={@timed_quiz_target}
                    current_quiz={@timed_current_quiz}
                    quiz_result={@timed_quiz_result}
                    quiz_answers={@timed_quiz_answers}
                    current_question_index={@timed_current_question_index}
                    time_expired?={@timed_quiz_time_expired?}
                    time_limit_seconds={@timed_quiz_time_limit_seconds}
                    deadline={@timed_quiz_deadline}
                  />
              <% end %>
          <% end %>
        </div>
      </div>
    </.student_layout>
    """
  end

  attr :enrollments, :list, required: true

  defp course_picker(assigns) do
    ~H"""
    <div class="p-8 lg:p-10">
      <h2 class="text-2xl font-semibold tracking-tight text-ink">Choose a course</h2>
      <div :if={@enrollments == []} class="mt-6 text-body">
        You don't have any active enrollments yet.
      </div>
      <div :if={@enrollments != []} class="mt-6 grid gap-3 sm:grid-cols-2">
        <button
          :for={enrollment <- @enrollments}
          type="button"
          phx-click="select-course"
          phx-value-slug={enrollment.course.slug}
          class="flex items-center justify-between gap-3 rounded-2xl border border-black/10 p-4 text-left text-sm text-body transition hover:border-primary/40 hover:bg-mint/40 hover:text-ink"
        >
          <span class="min-w-0">
            <span class="block truncate font-medium text-ink">{enrollment.course.title}</span>
            <span class="mt-0.5 block text-xs text-muted">
              {length(enrollment.course.modules)} modules
            </span>
          </span>
          <.icon name="hero-arrow-right" class="h-4 w-4 shrink-0 text-primary" />
        </button>
      </div>
    </div>
    """
  end

  attr :course, :map, required: true

  defp module_picker(assigns) do
    ~H"""
    <div class="p-8 lg:p-10">
      <button
        :if={length(@course.modules) > 0}
        type="button"
        phx-click="change-course"
        class="mb-6 inline-flex items-center gap-1.5 text-sm font-medium text-muted transition hover:text-primary"
      >
        <.icon name="hero-arrow-left" class="h-4 w-4" /> Choose a different course
      </button>
      <h2 class="text-2xl font-semibold tracking-tight text-ink">Choose a module</h2>
      <p class="mt-2 text-body">{@course.title}</p>
      <div :if={@course.modules == []} class="mt-6 text-body">
        This course doesn't have any modules yet.
      </div>
      <div :if={@course.modules != []} class="mt-6 grid gap-3 sm:grid-cols-2">
        <button
          :for={module <- @course.modules}
          type="button"
          phx-click="select-module"
          phx-value-module_id={module.id}
          class="flex items-center justify-between gap-3 rounded-2xl border border-black/10 p-4 text-left text-sm text-body transition hover:border-primary/40 hover:bg-mint/40 hover:text-ink"
        >
          <span class="min-w-0">
            <span class="block truncate font-medium text-ink">
              Module {module.position}: {module.title}
            </span>
            <span class="mt-0.5 block text-xs text-muted">{length(module.lectures)} lectures</span>
          </span>
          <.icon name="hero-arrow-right" class="h-4 w-4 shrink-0 text-primary" />
        </button>
      </div>
    </div>
    """
  end

  attr :course, :map, required: true
  attr :module, :map, required: true

  defp scope_picker(assigns) do
    ~H"""
    <div class="p-8 lg:p-10">
      <button
        type="button"
        phx-click="change-module"
        class="mb-6 inline-flex items-center gap-1.5 text-sm font-medium text-muted transition hover:text-primary"
      >
        <.icon name="hero-arrow-left" class="h-4 w-4" /> Choose a different module
      </button>
      <h2 class="text-2xl font-semibold tracking-tight text-ink">
        Study the whole module, or one lesson?
      </h2>
      <p class="mt-2 text-body">Module {@module.position}: {@module.title}</p>

      <div class="mt-6 grid gap-3 sm:grid-cols-2">
        <button
          type="button"
          phx-click="select-scope"
          phx-value-scope="module"
          class="flex items-center justify-between gap-3 rounded-2xl border border-black/10 p-4 text-left text-sm text-body transition hover:border-primary/40 hover:bg-mint/40 hover:text-ink"
        >
          <span class="min-w-0">
            <span class="block truncate font-medium text-ink">Whole module</span>
            <span class="mt-0.5 block text-xs text-muted">
              Covers all {length(@module.lectures)} lectures
            </span>
          </span>
          <.icon name="hero-arrow-right" class="h-4 w-4 shrink-0 text-primary" />
        </button>
        <button
          :for={lecture <- @module.lectures}
          type="button"
          phx-click="select-scope"
          phx-value-scope="lecture"
          phx-value-lecture_id={lecture.id}
          class="flex items-center justify-between gap-3 rounded-2xl border border-black/10 p-4 text-left text-sm text-body transition hover:border-primary/40 hover:bg-mint/40 hover:text-ink"
        >
          <span class="min-w-0">
            <span class="block truncate font-medium text-ink">{lecture.title}</span>
            <span class="mt-0.5 block text-xs text-muted">Just this lesson</span>
          </span>
          <.icon name="hero-arrow-right" class="h-4 w-4 shrink-0 text-primary" />
        </button>
      </div>
    </div>
    """
  end

  attr :course, :map, required: true
  attr :module, :map, required: true
  attr :scope, :map, required: true

  defp mode_picker(assigns) do
    ~H"""
    <div class="p-8 lg:p-10">
      <button
        type="button"
        phx-click="change-scope"
        class="mb-6 inline-flex items-center gap-1.5 text-sm font-medium text-muted transition hover:text-primary"
      >
        <.icon name="hero-arrow-left" class="h-4 w-4" /> Choose a different lesson
      </button>
      <h2 class="text-2xl font-semibold tracking-tight text-ink">What do you want to do?</h2>
      <p class="mt-2 text-body">{scope_label(@scope)}</p>

      <div class="mt-6 grid gap-3 sm:grid-cols-3">
        <button
          type="button"
          phx-click="select-mode"
          phx-value-mode="flashcards"
          class="flex flex-col items-start gap-3 rounded-2xl border border-black/10 p-5 text-left transition hover:border-primary/40 hover:bg-mint/40"
        >
          <span class="grid h-10 w-10 place-items-center rounded-full bg-mint text-primary">
            <.icon name="hero-rectangle-stack" class="h-5 w-5" />
          </span>
          <span class="font-semibold text-ink">Flashcards</span>
        </button>
        <button
          type="button"
          phx-click="select-mode"
          phx-value-mode="practice"
          class="flex flex-col items-start gap-3 rounded-2xl border border-black/10 p-5 text-left transition hover:border-primary/40 hover:bg-mint/40"
        >
          <span class="grid h-10 w-10 place-items-center rounded-full bg-mint text-primary">
            <.icon name="hero-pencil-square" class="h-5 w-5" />
          </span>
          <span class="font-semibold text-ink">Extra practice</span>
        </button>
        <button
          :if={match?(%CourseModule{}, @scope)}
          type="button"
          phx-click="select-mode"
          phx-value-mode="timed_quiz"
          class="flex flex-col items-start gap-3 rounded-2xl border border-black/10 p-5 text-left transition hover:border-primary/40 hover:bg-mint/40"
        >
          <span class="grid h-10 w-10 place-items-center rounded-full bg-mint text-primary">
            <.icon name="hero-clock" class="h-5 w-5" />
          </span>
          <span class="font-semibold text-ink">Timed quiz</span>
        </button>
      </div>
    </div>
    """
  end

  attr :course, :map, required: true
  attr :module, :map, required: true
  attr :scope, :map, required: true
  attr :mode, :atom, required: true

  defp content_breadcrumb(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2 border-b border-black/5 px-8 py-4 text-xs text-muted lg:px-10">
      <button type="button" phx-click="change-course" class="hover:text-primary">
        {@course.title}
      </button>
      <.icon name="hero-chevron-right" class="h-3 w-3" />
      <button type="button" phx-click="change-module" class="hover:text-primary">
        Module {@module.position}
      </button>
      <.icon name="hero-chevron-right" class="h-3 w-3" />
      <button type="button" phx-click="change-scope" class="hover:text-primary">
        {scope_label(@scope)}
      </button>
      <.icon name="hero-chevron-right" class="h-3 w-3" />
      <button type="button" phx-click="change-mode" class="font-medium text-ink hover:text-primary">
        {mode_label(@mode)}
      </button>
    </div>
    """
  end

  defp scope_label(%CourseModule{}), do: "Whole module"
  defp scope_label(%Lecture{title: title}), do: title

  defp mode_label(:flashcards), do: "Flashcards"
  defp mode_label(:practice), do: "Extra practice"
  defp mode_label(:timed_quiz), do: "Timed quiz"

  attr :target, :map, default: nil
  attr :current_quiz, :map, default: nil
  attr :quiz_result, :any, default: nil
  attr :quiz_answers, :map, required: true
  attr :current_question_index, :integer, required: true
  attr :time_expired?, :boolean, required: true
  attr :time_limit_seconds, :integer, default: nil
  attr :deadline, :any, default: nil

  defp timed_quiz_content(assigns) do
    ~H"""
    <%= if @current_quiz do %>
      <.quiz_taking_panel
        current_quiz={@current_quiz}
        quiz_result={@quiz_result}
        quiz_answers={@quiz_answers}
        current_question_index={@current_question_index}
        select_option_event="select-timed-quiz-option"
        submit_event="submit-timed-quiz"
        retake_event="retake-timed-quiz"
        next_event="timed-quiz-next"
        prev_event="timed-quiz-prev"
        time_expired?={@time_expired?}
        countdown={
          %{deadline: @deadline, total_seconds: length(@current_quiz.questions) * @time_limit_seconds}
        }
      />
    <% else %>
      <div class="p-8 lg:p-10">
        <%= if @target && @target.quiz && @target.question_count > 0 do %>
          <h2 class="text-2xl font-semibold tracking-tight text-ink">
            How much time do you want?
          </h2>
          <p class="mt-2 text-body">{@target.question_count} questions</p>

          <div class="mt-6 grid gap-3 sm:grid-cols-3">
            <button
              :for={{label, seconds_per_question} <- timed_quiz_presets()}
              type="button"
              phx-click="start-timed-quiz"
              phx-value-seconds-per-question={seconds_per_question}
              class="rounded-2xl border border-black/10 p-5 text-left transition hover:border-primary/40 hover:bg-mint/40"
            >
              <span class="block font-semibold text-ink">{label}</span>
              <span class="mt-1 block text-sm text-muted">
                {format_seconds(@target.question_count * seconds_per_question)} total
              </span>
            </button>
          </div>
        <% else %>
          <div class="grid min-h-[240px] place-items-center text-center text-muted">
            This module doesn't have a quiz yet.
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end
end
