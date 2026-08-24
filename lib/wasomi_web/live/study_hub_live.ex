defmodule WasomiWeb.StudyHubLive do
  @moduledoc """
  Cross-course self-study destination: Study guide, Flashcards, Extra practice,
  and Smart Test, scoped to any module (or a single lecture within it) across
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
  import WasomiWeb.CaptureProtection, only: [capture_guard_attrs: 1]

  alias Wasomi.Assessments
  alias Wasomi.Assessments.SmartTest
  alias Wasomi.Assessments.StudyGuide
  alias Wasomi.Assessments.Workers.GenerateFlashcardsWorker
  alias Wasomi.Assessments.Workers.GeneratePracticeSetQuestionsWorker
  alias Wasomi.Assessments.Workers.GenerateSmartTestWorker
  alias Wasomi.Assessments.Workers.GenerateStudyGuideWorker
  alias Wasomi.Accounts
  alias Wasomi.Catalog
  alias Wasomi.Catalog.CourseModule
  alias Wasomi.Catalog.Lecture
  alias Wasomi.Catalog.LectureResource
  alias Wasomi.Enrollments

  require Logger

  # Smart Test durations move in 5-minute steps, and a test shorter than one
  # step isn't a test.
  @min_duration_minutes 5

  @impl true
  def mount(params, session, socket) do
    current_user = socket.assigns[:current_user] || Accounts.get_user!(session["current_user_id"])
    enrollments = Enrollments.list_active_for_user(current_user)
    embedded? = session["embedded"] == true || params["embedded"] == "true"

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Study")
      |> assign(:embedded?, embedded?)
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
      |> assign(:smart_test, nil)
      |> assign(:smart_test_settings, default_smart_test_settings())
      |> assign(:smart_test_view, :settings)
      |> assign(:saved_smart_tests, [])
      |> assign(:smart_test_timer_ref, nil)
      |> assign(:study_guide, nil)
      |> assign(:study_guide_settings, default_study_guide_settings())
      |> assign(:study_guide_view, :brief)
      |> assign(:saved_study_guides, [])

    initial_params =
      if session["embedded"] == true,
        do: Map.take(session, ["course", "module", "mode", "scope", "lecture", "resource"]),
        else: params

    socket =
      socket
      |> resolve_scope_and_mode(initial_params)
      |> maybe_load_content()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:embedded?, params["embedded"] == "true")
     |> resolve_scope_and_mode(params)
     |> maybe_load_content()}
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

  # A single resource within the module. Fetched by id rather than found in an
  # already-loaded list (resources aren't preloaded on the enrollment's course),
  # so the id is confirmed against this module's own lectures before it is
  # trusted — otherwise the query param would read any course's resource.
  defp resolve_scope_selection(module, %{"scope" => "resource", "resource" => id}) do
    lecture_ids = MapSet.new(module.lectures, & &1.id)

    with {resource_id, ""} <- Integer.parse(to_string(id)),
         %LectureResource{} = resource <- Catalog.get_lecture_resource(resource_id),
         true <- MapSet.member?(lecture_ids, resource.lecture_id) do
      resource
    else
      _ -> nil
    end
  end

  defp resolve_scope_selection(_module, _params), do: nil

  # A single resource only has study-guide material to offer: flashcard and
  # practice sets are keyed to a module or lecture, and a Smart Test over one
  # handout isn't a test. Any other mode requested against a resource scope
  # falls back to the guide rather than crashing in `load_content/1`.
  defp resolve_mode(%LectureResource{}, _params), do: :study_guide
  defp resolve_mode(_scope, %{"mode" => "timed_quiz"}), do: :timed_quiz
  defp resolve_mode(_scope, %{"mode" => "flashcards"}), do: :flashcards
  defp resolve_mode(_scope, %{"mode" => "practice"}), do: :practice
  defp resolve_mode(_scope, %{"mode" => "study_guide"}), do: :study_guide
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
  defp scope_key(%LectureResource{id: id}), do: {:resource, id}
  defp scope_key(nil), do: nil

  # Flashcards are *not* generated on arrival: a `:pending` set renders the
  # setup panel instead, so the learner picks the module/lesson they actually
  # want cards for and asks for them explicitly. Generation costs an LLM call
  # per scope, and landing on this page is not the same as wanting a deck.
  defp load_content(%{assigns: %{mode: :flashcards, scope: scope}} = socket) do
    {:ok, set} = Assessments.get_or_create_flashcard_set(scope)
    Assessments.subscribe_to_flashcard_set(scope)
    load_flashcard_cards(socket, set)
  end

  defp load_content(%{assigns: %{mode: :practice, scope: scope}} = socket) do
    {:ok, quiz} = Assessments.get_or_create_practice_set(scope)
    maybe_enqueue_practice_generation(quiz)
    Assessments.subscribe_to_practice_set(scope)
    load_practice_set_questions(socket, quiz)
  end

  defp load_content(%{assigns: %{mode: :timed_quiz, scope: scope}} = socket) do
    user = socket.assigns.current_user
    smart_test = Assessments.latest_smart_test(user, scope)

    socket
    |> assign(:saved_smart_tests, Assessments.list_smart_tests(user, scope))
    |> assign(:smart_test, smart_test)
    |> assign(:smart_test_settings, smart_test_settings_from(smart_test))
    # Landing on the settings form rather than straight into an in-progress
    # test is deliberate: the learner asked for "Smart Test", not "resume",
    # and the saved-test row one screen down makes resuming one click away.
    |> assign(:smart_test_view, :settings)
    |> maybe_subscribe_to_smart_test(smart_test)
    |> schedule_smart_test_expiry()
  end

  # A guide is read rather than attempted, so — unlike a Smart Test — landing
  # here opens the last guide the learner wrote, and only falls back to the
  # brief when there is nothing to read yet.
  defp load_content(%{assigns: %{mode: :study_guide, scope: scope}} = socket) do
    user = socket.assigns.current_user
    study_guide = Assessments.latest_study_guide(user, scope)

    socket
    |> assign(:saved_study_guides, Assessments.list_study_guides(user, scope))
    |> assign(:study_guide, study_guide)
    |> assign(:study_guide_settings, study_guide_settings_from(study_guide))
    |> assign(:study_guide_view, if(study_guide, do: :guide, else: :brief))
    |> maybe_subscribe_to_study_guide(study_guide)
  end

  defp maybe_subscribe_to_smart_test(socket, %{status: status} = smart_test)
       when status in [:pending, :processing] do
    Assessments.subscribe_to_smart_test(smart_test)
    socket
  end

  defp maybe_subscribe_to_smart_test(socket, _smart_test), do: socket

  defp maybe_subscribe_to_study_guide(socket, %{status: status} = study_guide)
       when status in [:pending, :processing] do
    Assessments.subscribe_to_study_guide(study_guide)
    socket
  end

  defp maybe_subscribe_to_study_guide(socket, _study_guide), do: socket

  defp maybe_enqueue_practice_generation(%{status: :pending} = quiz),
    do: GeneratePracticeSetQuestionsWorker.enqueue(quiz.id)

  defp maybe_enqueue_practice_generation(_quiz), do: :ok

  ## Picker navigation

  # Reported by Hooks.CaptureGuard (throttled client-side). Advisory only: the
  # client is not trustworthy and the attempt is trivially avoidable, so this
  # feeds review, never enforcement. Same shape as CoursePlayerLive's clause.
  @impl true
  def handle_event("capture-attempt", %{"kind" => kind}, socket)
      when kind in ~w(copy printscreen shortcut:p shortcut:s) do
    Logger.warning(
      "capture attempt: kind=#{kind} user_id=#{socket.assigns.current_user.id} surface=study_hub"
    )

    {:noreply, socket}
  end

  def handle_event("capture-attempt", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select-course", %{"slug" => slug}, socket) do
    {:noreply, navigate_study(socket, %{course: slug})}
  end

  @impl true
  def handle_event("select-module", %{"module_id" => module_id}, socket) do
    course = socket.assigns.selected_course
    params = keep_mode(%{course: course.slug, module: module_id}, socket.assigns.mode)

    {:noreply, navigate_study(socket, params)}
  end

  # Re-scoping keeps the current mode when there is one: these buttons are
  # reachable both from the step-by-step picker (no mode yet) and from inside
  # a mode's own panel, where dropping back to the mode picker would be a
  # pointless extra click.
  @impl true
  def handle_event("select-scope", %{"scope" => "module"}, socket) do
    %{selected_course: course, selected_module: module} = socket.assigns

    params =
      keep_mode(%{course: course.slug, module: module.id, scope: "module"}, socket.assigns.mode)

    {:noreply, navigate_study(socket, params)}
  end

  @impl true
  def handle_event("select-scope", %{"scope" => "lecture", "lecture_id" => lecture_id}, socket) do
    %{selected_course: course, selected_module: module} = socket.assigns

    params =
      keep_mode(
        %{course: course.slug, module: module.id, scope: "lecture", lecture: lecture_id},
        socket.assigns.mode
      )

    {:noreply, navigate_study(socket, params)}
  end

  # A resource scope always lands on the study guide — see `resolve_mode/2` for
  # why it is the only mode a single document supports — so the mode is set here
  # rather than carried over from whatever the learner was last doing.
  @impl true
  def handle_event(
        "select-scope",
        %{"scope" => "resource", "resource_id" => resource_id},
        socket
      ) do
    %{selected_course: course, selected_module: module} = socket.assigns

    params = %{
      course: course.slug,
      module: module.id,
      scope: "resource",
      resource: resource_id,
      mode: "study_guide"
    }

    {:noreply, navigate_study(socket, params)}
  end

  @impl true
  def handle_event("select-mode", %{"mode" => mode}, socket) do
    params = Map.put(scope_params(socket.assigns), :mode, mode)
    {:noreply, navigate_study(socket, params)}
  end

  @impl true
  def handle_event("change-course", _params, socket) do
    {:noreply, navigate_study(socket, %{})}
  end

  @impl true
  def handle_event("change-module", _params, socket) do
    course = socket.assigns.selected_course
    params = keep_mode(%{course: course.slug}, socket.assigns.mode)
    {:noreply, navigate_study(socket, params)}
  end

  @impl true
  def handle_event("change-scope", _params, socket) do
    %{selected_course: course, selected_module: module} = socket.assigns
    params = keep_mode(%{course: course.slug, module: module.id}, socket.assigns.mode)

    {:noreply, navigate_study(socket, params)}
  end

  @impl true
  def handle_event("change-mode", _params, socket) do
    {:noreply, navigate_study(socket, scope_params(socket.assigns))}
  end

  ## Flashcards

  # Generation is always learner-initiated. The set is flipped to
  # `:processing` here rather than left `:pending` until the job picks it up,
  # so a reload (or a second learner on the same module) sees "generating"
  # instead of an untouched "Generate" button; the worker's own
  # `mark_flashcard_set_processing/1` is idempotent, and Oban's uniqueness on
  # `flashcard_set_id` means a double click can't queue two jobs.
  @impl true
  def handle_event("generate-flashcards", _params, socket) do
    case socket.assigns.flashcard_set do
      %{status: :pending} = set ->
        GenerateFlashcardsWorker.enqueue(set.id)
        {:noreply, load_flashcard_cards(socket, Assessments.mark_flashcard_set_processing(set))}

      _set ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("retry-flashcard-generation", _params, socket) do
    case socket.assigns.flashcard_set do
      %{status: :failed} = set ->
        GenerateFlashcardsWorker.enqueue(set.id)
        {:noreply, load_flashcard_cards(socket, Assessments.mark_flashcard_set_processing(set))}

      _set ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("regenerate-flashcards", _params, socket) do
    set = Assessments.reset_flashcard_set(socket.assigns.flashcard_set)
    GenerateFlashcardsWorker.enqueue(set.id)

    {:noreply, load_flashcard_cards(socket, Assessments.mark_flashcard_set_processing(set))}
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
    unresolved =
      Enum.filter(socket.assigns.flashcard_cards, fn %{progress: progress} ->
        is_nil(progress) or progress.status not in [:known, :mastered]
      end)

    cards = if unresolved == [], do: socket.assigns.flashcard_cards, else: unresolved

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

  ## Smart Test — a timed test generated to the learner's own settings, not
  ## the module's admin-authored Quiz: this is self-study, so there is no
  ## passing score, no submission that feeds progression, and no
  ## `module_quiz_unlocked?` gate, consistent with Flashcards/Practice being
  ## ungated everywhere.

  @impl true
  def handle_event("change-smart-test-settings", %{"settings" => params}, socket) do
    {:noreply,
     assign(socket, :smart_test_settings, merge_smart_test_settings(socket.assigns, params))}
  end

  @impl true
  def handle_event("step-smart-test-duration", %{"by" => by_str}, socket) do
    settings = socket.assigns.smart_test_settings
    by = String.to_integer(by_str)

    duration =
      (settings.duration_minutes + by)
      |> max(@min_duration_minutes)
      |> min(SmartTest.max_duration_minutes())

    {:noreply, assign(socket, :smart_test_settings, %{settings | duration_minutes: duration})}
  end

  @impl true
  def handle_event("create-smart-test", _params, socket) do
    %{current_user: user, scope: scope, smart_test_settings: settings} = socket.assigns

    case Assessments.create_smart_test(user, scope, settings) do
      {:ok, smart_test} ->
        GenerateSmartTestWorker.enqueue(smart_test.id)
        drop_previous_smart_test_subscription(socket.assigns.smart_test)
        Assessments.subscribe_to_smart_test(smart_test)

        {:noreply,
         socket
         |> assign(:smart_test, Assessments.load_smart_test_questions(smart_test))
         |> assign(:saved_smart_tests, Assessments.list_smart_tests(user, scope))
         |> assign(:smart_test_view, :test)}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, "Those test settings don't look right — try adjusting them.")}
    end
  end

  @impl true
  def handle_event("retry-smart-test-generation", _params, socket) do
    case socket.assigns.smart_test do
      %{status: :failed} = smart_test -> GenerateSmartTestWorker.enqueue(smart_test.id)
      _smart_test -> :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("open-smart-test", _params, socket) do
    {:noreply, assign(socket, :smart_test_view, :test)}
  end

  # Leaving an in-progress test for the settings form stops the clock, so
  # reading the settings never costs the learner test time.
  @impl true
  def handle_event("open-smart-test-settings", _params, socket) do
    {:noreply,
     socket
     |> pause_smart_test_attempt()
     |> assign(:smart_test_view, :settings)}
  end

  @impl true
  def handle_event("start-smart-test", _params, socket) do
    smart_test = socket.assigns.smart_test

    result =
      if smart_test.started_at,
        do: Assessments.resume_smart_test(smart_test),
        else: Assessments.start_smart_test(smart_test)

    case result do
      {:ok, started} ->
        {:noreply,
         socket
         |> put_smart_test(started)
         |> assign(:smart_test_view, :test)
         |> schedule_smart_test_expiry()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't start this test — please try again.")}
    end
  end

  @impl true
  def handle_event("pause-smart-test", _params, socket) do
    {:noreply, pause_smart_test_attempt(socket)}
  end

  @impl true
  def handle_event(
        "answer-smart-test-choice",
        %{"question-id" => question_id, "option-id" => option_id},
        socket
      ) do
    {:noreply, record_smart_test_answer(socket, question_id, option_id)}
  end

  @impl true
  def handle_event(
        "answer-smart-test-text",
        %{"question_id" => question_id, "response" => response},
        socket
      ) do
    {:noreply, record_smart_test_answer(socket, question_id, response)}
  end

  @impl true
  def handle_event("finish-smart-test", _params, socket) do
    {:noreply, finish_smart_test_attempt(socket, false)}
  end

  @impl true
  def handle_event("retake-smart-test", _params, socket) do
    case Assessments.reset_smart_test(socket.assigns.smart_test) do
      {:ok, reset} ->
        {:noreply, socket |> put_smart_test(reset) |> assign(:smart_test_view, :test)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  ## Study guide

  @impl true
  def handle_event("change-study-guide-settings", %{"settings" => params}, socket) do
    {:noreply,
     assign(socket, :study_guide_settings, merge_study_guide_settings(socket.assigns, params))}
  end

  @impl true
  def handle_event("create-study-guide", params, socket) do
    # The submit payload is authoritative when it carries the form (a click on
    # the button blurs the focus textarea, but a submit can still arrive without
    # a preceding change event), so the brief is re-read from it rather than
    # trusting whatever the last change event happened to leave in assigns.
    settings =
      case params do
        %{"settings" => submitted} -> merge_study_guide_settings(socket.assigns, submitted)
        _no_form -> socket.assigns.study_guide_settings
      end

    %{current_user: user, scope: scope} = socket.assigns
    socket = assign(socket, :study_guide_settings, settings)

    case Assessments.create_study_guide(user, scope, settings) do
      {:ok, study_guide} ->
        GenerateStudyGuideWorker.enqueue(study_guide.id)
        drop_previous_study_guide_subscription(socket.assigns.study_guide)
        Assessments.subscribe_to_study_guide(study_guide)

        {:noreply,
         socket
         |> assign(:study_guide, Assessments.load_study_guide_sections(study_guide))
         |> assign(:saved_study_guides, Assessments.list_study_guides(user, scope))
         |> assign(:study_guide_view, :guide)}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, "Those guide settings don't look right — try adjusting them.")}
    end
  end

  @impl true
  def handle_event("open-study-guide", %{"id" => id}, socket) do
    case Assessments.get_user_study_guide(socket.assigns.current_user, id) do
      nil ->
        {:noreply, socket}

      study_guide ->
        drop_previous_study_guide_subscription(socket.assigns.study_guide)

        {:noreply,
         socket
         |> assign(:study_guide, study_guide)
         |> assign(:study_guide_settings, study_guide_settings_from(study_guide))
         |> assign(:study_guide_view, :guide)
         |> maybe_subscribe_to_study_guide(study_guide)}
    end
  end

  @impl true
  def handle_event("open-study-guide-brief", _params, socket) do
    {:noreply, assign(socket, :study_guide_view, :brief)}
  end

  @impl true
  def handle_event("delete-study-guide", %{"id" => id}, socket) do
    %{current_user: user, scope: scope, study_guide: open_guide} = socket.assigns

    case Assessments.delete_user_study_guide(user, id) do
      {:ok, deleted} ->
        drop_previous_study_guide_subscription(deleted)
        socket = assign(socket, :saved_study_guides, Assessments.list_study_guides(user, scope))

        # Deleting the guide currently loaded leaves nothing to go back to, so
        # it's dropped rather than left behind as a stale document.
        if open_guide && open_guide.id == deleted.id do
          {:noreply,
           socket
           |> assign(:study_guide, nil)
           |> assign(:study_guide_view, :brief)}
        else
          {:noreply, socket}
        end

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("retry-study-guide-generation", _params, socket) do
    case socket.assigns.study_guide do
      %{status: :failed} = study_guide -> GenerateStudyGuideWorker.enqueue(study_guide.id)
      _study_guide -> :ok
    end

    {:noreply, socket}
  end

  defp keep_mode(params, nil), do: params
  defp keep_mode(params, mode), do: Map.put(params, :mode, to_string(mode))

  defp navigate_study(%{assigns: %{embedded?: true}} = socket, params) do
    socket
    |> resolve_scope_and_mode(
      Map.new(params, fn {key, value} -> {to_string(key), to_string(value)} end)
    )
    |> maybe_load_content()
  end

  defp navigate_study(socket, params), do: push_patch(socket, to: ~p"/learn/study?#{params}")

  defp scope_params(%{
         selected_course: course,
         selected_module: module,
         scope: %LectureResource{} = resource
       }) do
    %{course: course.slug, module: module.id, scope: "resource", resource: resource.id}
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
  defp safe_flashcard_rating("mastered"), do: :mastered
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

  ## Smart Test helpers

  # Form params arrive as strings and can be hand-edited, so every value is
  # parsed and clamped here rather than trusted; anything unparseable keeps
  # its current value instead of resetting the form.
  defp merge_smart_test_settings(assigns, params) do
    settings = assigns.smart_test_settings

    %{
      duration_minutes:
        clamp_setting(
          params["duration_minutes"],
          settings.duration_minutes,
          @min_duration_minutes,
          SmartTest.max_duration_minutes()
        ),
      enforce_time_limit: params["enforce_time_limit"] == "true",
      multiple_choice_count:
        clamp_setting(
          params["multiple_choice_count"],
          settings.multiple_choice_count,
          0,
          SmartTest.max_multiple_choice()
        ),
      short_answer_count:
        clamp_setting(
          params["short_answer_count"],
          settings.short_answer_count,
          0,
          SmartTest.max_short_answer()
        ),
      difficulty: clamp_setting(params["difficulty"], settings.difficulty, 1, 5)
    }
  end

  defp clamp_setting(value, fallback, min, max) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _rest} -> parsed |> max(min) |> min(max)
      :error -> fallback
    end
  end

  defp clamp_setting(_value, fallback, _min, _max), do: fallback

  defp record_smart_test_answer(socket, question_id, answer) do
    smart_test = socket.assigns.smart_test

    question =
      Enum.find(smart_test.smart_test_questions, &(to_string(&1.id) == to_string(question_id)))

    # An answer after the clock ran out (or after finishing) must not land —
    # the deadline expiring auto-submits, and a late in-flight event would
    # otherwise edit an already-scored attempt.
    if question && is_nil(smart_test.completed_at) do
      case Assessments.record_smart_test_answer(question, answer) do
        {:ok, _updated} -> put_smart_test(socket, smart_test)
        {:error, _reason} -> socket
      end
    else
      socket
    end
  end

  defp finish_smart_test_attempt(socket, time_expired?) do
    smart_test = socket.assigns.smart_test

    if smart_test && is_nil(smart_test.completed_at) do
      socket = cancel_smart_test_timer(socket)

      case Assessments.finish_smart_test(smart_test, time_expired: time_expired?) do
        {:ok, finished} ->
          socket
          |> put_smart_test(finished)
          |> assign(:smart_test_view, :test)

        {:error, _changeset} ->
          put_flash(socket, :error, "Couldn't score this test — please try again.")
      end
    else
      socket
    end
  end

  defp pause_smart_test_attempt(socket) do
    smart_test = socket.assigns.smart_test

    if smart_test && smart_test.started_at && is_nil(smart_test.completed_at) do
      case Assessments.pause_smart_test(smart_test) do
        {:ok, paused} -> socket |> cancel_smart_test_timer() |> put_smart_test(paused)
        {:error, _changeset} -> socket
      end
    else
      socket
    end
  end

  # Always re-reads the questions, since answers and scores live on them.
  defp put_smart_test(socket, smart_test) do
    loaded = Assessments.load_smart_test_questions(smart_test)

    socket
    |> assign(:smart_test, loaded)
    |> assign(
      :saved_smart_tests,
      Assessments.list_smart_tests(socket.assigns.current_user, socket.assigns.scope)
    )
  end

  # The server owns the deadline: the countdown in the browser is display-only
  # (see the `QuizCountdown` hook), so expiry has to be scheduled here. Also
  # called on load, so a learner who closed the tab mid-test and came back
  # after the deadline gets scored instead of finding a stopped clock.
  defp schedule_smart_test_expiry(socket) do
    socket = cancel_smart_test_timer(socket)

    case socket.assigns.smart_test do
      %{started_at: started, paused_at: nil, completed_at: nil, expires_at: expires}
      when not is_nil(started) and not is_nil(expires) ->
        remaining = Assessments.smart_test_remaining_seconds(socket.assigns.smart_test)
        ref = Process.send_after(self(), :smart_test_expired, remaining * 1000)
        assign(socket, :smart_test_timer_ref, ref)

      _not_running ->
        socket
    end
  end

  defp cancel_smart_test_timer(socket) do
    case socket.assigns.smart_test_timer_ref do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end

    assign(socket, :smart_test_timer_ref, nil)
  end

  defp drop_previous_smart_test_subscription(nil), do: :ok

  defp drop_previous_smart_test_subscription(smart_test),
    do: Assessments.unsubscribe_from_smart_test(smart_test)

  defp drop_previous_study_guide_subscription(nil), do: :ok

  defp drop_previous_study_guide_subscription(study_guide),
    do: Assessments.unsubscribe_from_study_guide(study_guide)

  # Brief params arrive as strings and can be hand-edited, so each dial is
  # matched against the values the schema allows rather than trusted; anything
  # unrecognised keeps its current value instead of resetting the form.
  defp merge_study_guide_settings(assigns, params) do
    settings = assigns.study_guide_settings

    %{
      style: safe_study_guide_choice(params["style"], StudyGuide.styles(), settings.style),
      depth: safe_study_guide_choice(params["depth"], StudyGuide.depths(), settings.depth),
      reading_level:
        safe_study_guide_choice(
          params["reading_level"],
          StudyGuide.reading_levels(),
          settings.reading_level
        ),
      include_examples: params["include_examples"] == "true",
      include_key_terms: params["include_key_terms"] == "true",
      focus: params["focus"]
    }
  end

  defp safe_study_guide_choice(value, allowed, fallback) when is_binary(value) do
    Enum.find(allowed, fallback, &(to_string(&1) == value))
  end

  defp safe_study_guide_choice(_value, _allowed, fallback), do: fallback

  defp smart_test_remaining_seconds(nil), do: nil

  defp smart_test_remaining_seconds(smart_test),
    do: Assessments.smart_test_remaining_seconds(smart_test)

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
  def handle_info({:smart_test_updated, smart_test}, socket) do
    if socket.assigns.smart_test && socket.assigns.smart_test.id == smart_test.id do
      {:noreply, put_smart_test(socket, smart_test)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:smart_test_expired, socket) do
    {:noreply,
     socket
     |> assign(:smart_test_timer_ref, nil)
     |> finish_smart_test_attempt(true)}
  end

  @impl true
  def handle_info({:study_guide_updated, study_guide}, socket) do
    if socket.assigns.study_guide && socket.assigns.study_guide.id == study_guide.id do
      {:noreply,
       socket
       |> assign(:study_guide, Assessments.load_study_guide_sections(study_guide))
       |> assign(
         :saved_study_guides,
         Assessments.list_study_guides(socket.assigns.current_user, socket.assigns.scope)
       )}
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
    <div
      id="study-hub"
      class={if @embedded?, do: "embedded-study-hub", else: ""}
      {capture_guard_attrs(@current_user)}
    >
      <.student_layout active={:study} current_user={@current_user} embedded={@embedded?}>
        <div
          id="study-hub-scroll-boundary"
          phx-hook="ScrollContainerOnKeyChange"
          data-scroll-key={study_hub_scroll_key(assigns)}
          class={if @embedded?, do: "w-full p-5 lg:p-8", else: "w-full px-5 py-8 lg:px-8"}
        >
          <h1 :if={!@embedded?} class="text-3xl font-semibold tracking-tight text-ink sm:text-4xl">
            Study
          </h1>
          <p :if={!@embedded?} class="mt-2 text-body">
            Study guides, flashcards, extra practice, and timed Smart Tests — generated from
            your course materials, across everything you're enrolled in.
          </p>

          <div class={
            if @embedded?,
              do: "overflow-hidden rounded-3xl border border-black/5 bg-white",
              else: "mt-8 overflow-hidden rounded-3xl border border-black/5 bg-white"
          }>
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
                      module={@selected_module}
                      scope={@scope}
                    />
                  <% :practice -> %>
                    <.practice_set_panel
                      practice_set={@practice_set}
                      practice_set_questions={@practice_set_questions}
                      practice_answers={@practice_answers}
                      practice_index={@practice_index}
                    />
                  <% :timed_quiz -> %>
                    <.smart_test_panel
                      smart_test={@smart_test}
                      settings={@smart_test_settings}
                      scope_label={material_label(@scope)}
                      view={@smart_test_view}
                      remaining_seconds={smart_test_remaining_seconds(@smart_test)}
                      saved_tests={@saved_smart_tests}
                    />
                  <% :study_guide -> %>
                    <.study_guide_panel
                      study_guide={@study_guide}
                      settings={@study_guide_settings}
                      scope_label={material_label(@scope)}
                      view={@study_guide_view}
                      saved_guides={@saved_study_guides}
                    />
                <% end %>
            <% end %>
          </div>
        </div>
      </.student_layout>
    </div>
    """
  end

  defp study_hub_scroll_key(assigns) do
    [
      assigns.step,
      assigns.selected_course && assigns.selected_course.id,
      assigns.selected_module && assigns.selected_module.id,
      scope_key(assigns.scope),
      assigns.mode
    ]
    |> Enum.map_join(":", &inspect/1)
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

      <div class="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <button
          type="button"
          phx-click="select-mode"
          phx-value-mode="study_guide"
          class="flex flex-col items-start gap-3 rounded-2xl border border-black/10 p-5 text-left transition hover:border-primary/40 hover:bg-mint/40"
        >
          <span class="grid h-10 w-10 place-items-center rounded-full bg-mint text-primary">
            <.icon name="hero-light-bulb" class="h-5 w-5" />
          </span>
          <span class="font-semibold text-ink">Study guide</span>
          <span class="text-sm text-muted">
            Short notes on this material, in the style you pick.
          </span>
        </button>
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
          <span class="text-sm text-muted">
            Recall drills built from this module's practice questions.
          </span>
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
          type="button"
          phx-click="select-mode"
          phx-value-mode="timed_quiz"
          class="flex flex-col items-start gap-3 rounded-2xl border border-black/10 p-5 text-left transition hover:border-primary/40 hover:bg-mint/40"
        >
          <span class="grid h-10 w-10 place-items-center rounded-full bg-mint text-primary">
            <.icon name="hero-clipboard-document-check" class="h-5 w-5" />
          </span>
          <span class="font-semibold text-ink">Smart Test</span>
          <span class="text-sm text-muted">
            A timed test built to your own length, mix and difficulty.
          </span>
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
    <div class="flex flex-wrap items-center gap-x-4 gap-y-3 border-b border-black/5 px-8 py-4 lg:px-10">
      <button
        type="button"
        phx-click="change-mode"
        class="inline-flex items-center gap-1.5 rounded-full border border-black/10 px-4 py-2 text-sm font-semibold text-ink transition hover:border-primary/40 hover:bg-mint/40 hover:text-primary"
      >
        <.icon name="hero-arrow-left" class="h-4 w-4" /> Back to study options
      </button>
      <div class="flex flex-wrap items-center gap-2 text-xs text-muted">
        <button
          type="button"
          phx-click="change-course"
          class="underline-offset-4 hover:text-primary hover:underline"
        >
          {@course.title}
        </button>
        <.icon name="hero-chevron-right" class="h-3 w-3" />
        <button
          type="button"
          phx-click="change-module"
          class="underline-offset-4 hover:text-primary hover:underline"
        >
          Module {@module.position}
        </button>
        <.icon name="hero-chevron-right" class="h-3 w-3" />
        <button
          type="button"
          phx-click="change-scope"
          class="underline-offset-4 hover:text-primary hover:underline"
        >
          {scope_label(@scope)}
        </button>
        <.icon name="hero-chevron-right" class="h-3 w-3" />
        <span class="font-semibold text-ink">{mode_label(@mode)}</span>
      </div>
    </div>
    """
  end

  defp scope_label(%CourseModule{}), do: "Whole module"
  defp scope_label(%Lecture{title: title}), do: title
  defp scope_label(%LectureResource{name: name}), do: name

  # The Smart Test and Study guide headers name the material itself rather than
  # "Whole module", since each reads as the test's (or the document's) title.
  defp material_label(%CourseModule{title: title}), do: title
  defp material_label(%Lecture{title: title}), do: title
  defp material_label(%LectureResource{name: name}), do: name

  defp mode_label(:flashcards), do: "Flashcards"
  defp mode_label(:practice), do: "Extra practice"
  defp mode_label(:study_guide), do: "Study guide"
  defp mode_label(:timed_quiz), do: "Smart Test"
end
