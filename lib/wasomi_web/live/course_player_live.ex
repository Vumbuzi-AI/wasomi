defmodule WasomiWeb.CoursePlayerLive do
  @moduledoc """
  The learner course player, and (via the `:preview` `live_action`, only
  reachable under the admin-gated `/admin/courses/:slug/preview` route) the
  admin "view as learner" preview mode.

  Preview mode reuses this exact module — same markup, same navigation,
  same lecture-unlock rules — rather than a parallel LiveView, so what an
  admin sees is provably what a learner sees. Two things differ, both
  gated on `@preview?`:

    * The pay-gate is skipped entirely for `@preview?`, rather than via any
      bypass in `Wasomi.Enrollments` — that module's checks stay pay-gate-only
      for every caller, admin or not. `@preview?` is only ever true when
      `live_action == :preview`, which is itself only reachable through the
      admin-gated `/admin/courses/:slug/preview` route, so this can't be
      reached by a non-admin.
    * Progress is never persisted. Real learners' progress comes from
      `Wasomi.Learning` (backed by the `lecture_progress` table); preview
      progress lives only in `@preview_progress`, a plain map kept in the
      socket for the life of the LiveView process. Closing the tab discards
      it — nothing is ever written for the admin's own user, so preview
      clicks can never pollute real completion analytics.

  Both progress sources are fed through the same `Learning.summarize_progress/2`
  and the same local unlock/next-lecture logic, so the two modes can't drift
  apart in how they compute "is this lecture unlocked."
  """

  use WasomiWeb, :live_view

  alias Wasomi.{Assessments, Catalog, Certificates, Enrollments, Learning}

  import WasomiWeb.StudyComponents, only: [quiz_taking_panel: 1]

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    preview? = socket.assigns.live_action == :preview
    # Status-agnostic on purpose — access is gated by enrollment below, not
    # status, so an archived course's enrolled learners keep working.
    course = Catalog.get_course_by_slug!(slug)

    authorization =
      if preview?,
        do: {:ok, course},
        else: Enrollments.authorize_course(socket.assigns.current_user, course)

    case authorization do
      {:ok, course} ->
        if connected?(socket) and not preview? do
          Learning.subscribe(socket.assigns.current_user)
          Certificates.subscribe(socket.assigns.current_user)
        end

        quizzes_by_module = Assessments.get_quizzes_by_module(course.id)
        practice_by_module = Assessments.published_practice_questions_by_module(course.id)

        completed_quiz_ids =
          if preview? do
            MapSet.new()
          else
            Assessments.completed_quiz_ids_for_user(socket.assigns.current_user.id, course.id)
          end

        {:ok,
         socket
         |> assign(:page_title, preview_page_title(course, preview?))
         |> assign(:course, course)
         |> assign(:quizzes_by_module, quizzes_by_module)
         |> assign(:practice_by_module, practice_by_module)
         |> assign(:completed_quiz_ids, completed_quiz_ids)
         |> assign(:current_quiz, nil)
         |> assign(:quiz_answers, %{})
         |> assign(:quiz_result, nil)
         |> assign(:current_question_index, 0)
         |> assign(:current_practice_module, nil)
         |> assign(:practice_answers, %{})
         |> assign(:generating_practice?, false)
         |> assign(:active_section, :lessons)
         |> assign(:preview?, preview?)
         |> assign(:preview_progress, %{})
         |> assign(:lq_submissions, %{})
         |> refresh_progress()}

      {:error, :forbidden} when course.status == :published ->
        {:ok,
         socket
         |> put_flash(:error, "Complete enrollment to access course content.")
         |> redirect(to: ~p"/courses/#{course.slug}/checkout")}

      {:error, :forbidden} ->
        {:ok,
         socket
         |> put_flash(:error, "This course isn't available.")
         |> redirect(to: ~p"/courses")}
    end
  end

  defp preview_page_title(course, true), do: "Preview · #{course.title}"
  defp preview_page_title(course, false), do: course.title

  # `preview=true` is only ever honored server-side (WasomiWeb.MediaController)
  # if the authenticated session user is actually an admin, so a non-admin
  # copying this URL gains nothing — the real gate stays intact for them.
  defp playback_url_path(lecture_id, true),
    do: ~p"/media/lectures/#{lecture_id}/playback?preview=true"

  defp playback_url_path(lecture_id, false), do: ~p"/media/lectures/#{lecture_id}/playback"

  # Same trust boundary as `playback_url_path/2` above — `preview=true` is
  # only ever honored server-side (WasomiWeb.ResourceController) after
  # confirming the session user is actually an admin.
  defp resource_download_path(resource_id, true),
    do: ~p"/learn/resources/#{resource_id}/download?preview=true"

  defp resource_download_path(resource_id, false),
    do: ~p"/learn/resources/#{resource_id}/download"

  defp resource_icon(:document), do: "hero-document-text"
  defp resource_icon(:video), do: "hero-film"
  defp resource_icon(:link), do: "hero-link"

  @sections ~w(lessons module_quiz)a

  @impl true
  def handle_event("select-section", %{"section" => section_str}, socket) do
    case safe_section(section_str) do
      {:ok, section} -> {:noreply, enter_section(socket, section)}
      :error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("exit-quiz", _params, socket) do
    {:noreply,
     socket
     |> assign(:current_quiz, nil)
     |> assign(:quiz_result, nil)
     |> assign(:quiz_answers, %{})
     |> assign(:current_question_index, 0)}
  end

  @impl true
  def handle_event("select-lecture", %{"id" => id}, socket) do
    lecture = find_lecture(socket.assigns.course, id)

    if lecture && lecture_unlocked?(socket.assigns.unlocked_lecture_ids, lecture.id) do
      {:noreply,
       socket
       |> assign(:current_quiz, nil)
       |> assign(:quiz_result, nil)
       |> assign(:current_lecture, lecture)
       |> assign(:lq_submissions, load_lq_submissions(socket, lecture))
       |> assign(:page_title, lecture_page_title(socket, lecture))}
    else
      {:noreply, put_flash(socket, :error, "Complete the previous lecture to unlock this one.")}
    end
  end

  @impl true
  def handle_event("select-quiz", %{"module_id" => module_id_str}, socket) do
    module = Enum.find(socket.assigns.course.modules, &(to_string(&1.id) == module_id_str))

    if module do
      case Map.get(socket.assigns.quizzes_by_module, module.id) do
        nil ->
          {:noreply, put_flash(socket, :error, "No quiz is available for this module yet.")}

        quiz ->
          cond do
            not module_quiz_unlocked?(module, socket.assigns.progress, socket.assigns.preview?) ->
              {:noreply,
               put_flash(socket, :error, "Complete this module's lectures to unlock its quiz.")}

            Assessments.list_published_questions(quiz) == [] ->
              {:noreply,
               put_flash(socket, :error, "This quiz does not have any published questions yet.")}

            true ->
              questions = Assessments.list_published_questions(quiz)

              existing_submission =
                if socket.assigns.preview? do
                  nil
                else
                  user_submissions =
                    Assessments.list_submissions_for_user(socket.assigns.current_user, quiz)

                  List.first(user_submissions)
                end

              quiz_answers =
                if existing_submission do
                  Map.new(existing_submission.answers, fn {k, v} ->
                    {to_string(k), v && to_string(v)}
                  end)
                else
                  %{}
                end

              {:noreply,
               socket
               |> assign(:current_lecture, nil)
               |> assign(:current_quiz, %{quiz: quiz, module: module, questions: questions})
               |> assign(:quiz_answers, quiz_answers)
               |> assign(:quiz_result, existing_submission)
               |> assign(:current_question_index, 0)
               |> assign(
                 :page_title,
                 "Module Quiz: #{module.title} · #{socket.assigns.course.title}"
               )}
          end
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "select-quiz-option",
        %{"question-id" => q_id, "option-id" => opt_id},
        socket
      ) do
    quiz_answers = Map.put(socket.assigns.quiz_answers, to_string(q_id), to_string(opt_id))
    {:noreply, assign(socket, :quiz_answers, quiz_answers)}
  end

  @impl true
  def handle_event("submit-quiz", _params, socket) do
    case socket.assigns.current_quiz do
      %{quiz: quiz, questions: questions} ->
        answers = socket.assigns.quiz_answers

        if socket.assigns.preview? do
          result = preview_quiz_result(quiz, questions, answers)
          {:noreply, assign(socket, :quiz_result, result)}
        else
          case Assessments.submit_quiz(socket.assigns.current_user, quiz, answers) do
            {:ok, submission} ->
              completed_quiz_ids = MapSet.put(socket.assigns.completed_quiz_ids, quiz.id)

              {:noreply,
               socket
               |> assign(:quiz_result, submission)
               |> assign(:completed_quiz_ids, completed_quiz_ids)
               |> put_flash(:info, "Quiz submitted successfully!")}

            {:error, :quiz_not_ready} ->
              {:noreply, put_flash(socket, :error, "This quiz is not ready for submission.")}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Could not submit quiz.")}
          end
        end

      nil ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("retake-quiz", _params, socket) do
    {:noreply,
     socket
     |> assign(:quiz_result, nil)
     |> assign(:quiz_answers, %{})
     |> assign(:current_question_index, 0)}
  end

  @impl true
  def handle_event(
        "submit-lecture-question",
        %{"question-id" => q_id, "answer" => answer_text},
        socket
      ) do
    if socket.assigns.preview? do
      {:noreply, socket}
    else
      question =
        Enum.find(socket.assigns.current_lecture.questions, &(to_string(&1.id) == q_id))

      if question do
        case Catalog.submit_lecture_question_answer(
               socket.assigns.current_user,
               question,
               String.trim(answer_text)
             ) do
          {:ok, submission} ->
            submissions =
              Map.put(socket.assigns.lq_submissions, submission.lecture_question_id, submission)

            {:noreply, assign(socket, :lq_submissions, submissions)}

          {:error, _reason} ->
            {:noreply,
             put_flash(socket, :error, "Could not score your answer. Please try again.")}
        end
      else
        {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("start-practice", %{"module_id" => module_id_str}, socket) do
    module = Enum.find(socket.assigns.course.modules, &(to_string(&1.id) == module_id_str))

    if module do
      if practice_questions_unlocked?(
           module,
           socket.assigns.quizzes_by_module,
           socket.assigns.completed_quiz_ids,
           socket.assigns.progress,
           socket.assigns.preview?
         ) do
        questions = Map.get(socket.assigns.practice_by_module, module.id, [])

        {:noreply,
         socket
         |> assign(:current_lecture, nil)
         |> assign(:current_quiz, nil)
         |> assign(:current_practice_module, %{module: module, questions: questions})
         |> assign(:practice_answers, %{})
         |> assign(:page_title, "Practice · #{module.title} · #{socket.assigns.course.title}")}
      else
        {:noreply,
         put_flash(
           socket,
           :error,
           "Complete the module quiz first to unlock extra practice questions."
         )}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("generate-practice-questions", %{"module_id" => module_id_str}, socket) do
    module = Enum.find(socket.assigns.course.modules, &(to_string(&1.id) == module_id_str))

    if module && !socket.assigns.generating_practice? do
      {:noreply,
       socket
       |> assign(:generating_practice?, true)
       |> start_async({:generate_practice_questions, module.id}, fn ->
         Assessments.generate_practice_questions_for_module(module, count: 5)
       end)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "submit-practice-answer",
        %{"question-id" => q_id, "option-id" => opt_id},
        socket
      ) do
    questions = socket.assigns.current_practice_module.questions
    question = Enum.find(questions, &(to_string(&1.id) == q_id))

    if question && !Map.has_key?(socket.assigns.practice_answers, q_id) do
      opt_id_str = to_string(opt_id)

      correct? =
        Enum.any?(
          question.practice_question_options,
          &(to_string(&1.id) == opt_id_str and &1.correct)
        )

      answer = %{option_id: opt_id_str, correct?: correct?}

      {:noreply,
       assign(socket, :practice_answers, Map.put(socket.assigns.practice_answers, q_id, answer))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next-question", _params, socket) do
    last_index = length(socket.assigns.current_quiz.questions) - 1
    next_index = min(socket.assigns.current_question_index + 1, last_index)
    {:noreply, assign(socket, :current_question_index, next_index)}
  end

  @impl true
  def handle_event("prev-question", _params, socket) do
    prev_index = max(socket.assigns.current_question_index - 1, 0)
    {:noreply, assign(socket, :current_question_index, prev_index)}
  end

  @impl true
  def handle_event(
        "video-progress",
        %{"lecture_id" => lecture_id, "position_seconds" => position},
        socket
      ) do
    case current_lecture(socket, lecture_id) do
      nil ->
        {:noreply, socket}

      lecture ->
        if socket.assigns.preview? do
          {:noreply,
           socket
           |> put_preview_progress(lecture.id, :in_progress, position)
           |> refresh_progress()}
        else
          persist_progress(socket, lecture, position, false)
        end
    end
  end

  @impl true
  def handle_event("complete-lecture", %{"lecture_id" => lecture_id}, socket) do
    case current_lecture(socket, lecture_id) do
      nil ->
        {:noreply, socket}

      lecture ->
        cond do
          not (is_nil(lecture.duration_seconds) or
                   Learning.watched_enough?(
                     progress_position(socket.assigns.progress, lecture.id),
                     lecture.duration_seconds
                   )) ->
            {:noreply,
             put_flash(socket, :error, "Watch more of this lecture before marking it complete.")}

          socket.assigns.preview? ->
            {:noreply,
             socket
             |> put_preview_progress(lecture.id, :completed, lecture.duration_seconds || 0)
             |> refresh_progress()
             |> put_flash(:info, "Lecture marked complete — preview only, nothing was saved.")}

          true ->
            persist_progress(socket, lecture, lecture.duration_seconds, true)
        end
    end
  end

  defp safe_section(section_str) do
    section = String.to_existing_atom(section_str)
    if section in @sections, do: {:ok, section}, else: :error
  rescue
    ArgumentError -> :error
  end

  defp enter_section(socket, :module_quiz = section) do
    socket
    |> assign(:active_section, section)
    |> maybe_auto_select_module_quiz()
  end

  defp enter_section(socket, section), do: assign(socket, :active_section, section)

  # A single-module course has nothing to pick, so skip the module picker and
  # go straight to that module's quiz — mirrors what a learner would do
  # manually anyway, without an extra click for a "choice" that isn't one.
  defp maybe_auto_select_module_quiz(socket) do
    case socket.assigns.course.modules do
      [module] -> select_quiz_silently(socket, module)
      _modules -> socket
    end
  end

  defp select_quiz_silently(socket, module) do
    if socket.assigns.current_quiz do
      socket
    else
      with quiz when not is_nil(quiz) <- Map.get(socket.assigns.quizzes_by_module, module.id),
           true <-
             module_quiz_unlocked?(module, socket.assigns.progress, socket.assigns.preview?),
           questions when questions != [] <- Assessments.list_published_questions(quiz) do
        existing_submission =
          if socket.assigns.preview? do
            nil
          else
            socket.assigns.current_user
            |> Assessments.list_submissions_for_user(quiz)
            |> List.first()
          end

        socket
        |> assign(:current_lecture, nil)
        |> assign(:current_quiz, %{quiz: quiz, module: module, questions: questions})
        |> assign(:quiz_answers, %{})
        |> assign(:quiz_result, existing_submission)
        |> assign(:current_question_index, 0)
      else
        _ -> socket
      end
    end
  end

  # Shared by the untimed "submit-quiz" handler and the timed quiz's own
  # scoring path — an admin previewing never gets a persisted
  # `QuizSubmission`, so both compute the same shape in memory instead.
  defp preview_quiz_result(quiz, questions, answers) do
    normalized = Map.new(answers, fn {k, v} -> {to_string(k), to_string(v)} end)

    correct_count =
      Enum.count(questions, fn q ->
        selected = Map.get(normalized, to_string(q.id))
        Enum.any?(q.question_options, &(to_string(&1.id) == selected and &1.correct))
      end)

    score_percent =
      if questions != [], do: round(correct_count / length(questions) * 100), else: 0

    %{
      score_percent: score_percent,
      passed: score_percent >= quiz.passing_score_percent,
      preview?: true,
      correct_count: correct_count,
      total_count: length(questions)
    }
  end

  defp persist_progress(socket, lecture, position, explicit_complete?) do
    result =
      if explicit_complete? do
        Learning.mark_complete(socket.assigns.current_user, lecture)
      else
        Learning.record_progress(socket.assigns.current_user, lecture, position)
      end

    case result do
      {:ok, _progress, _events} when explicit_complete? ->
        {:noreply,
         socket
         |> refresh_progress()
         |> put_flash(:info, "Lecture completed. The next lesson is now unlocked.")}

      {:ok, _progress, _events} ->
        {:noreply, refresh_progress(socket)}

      {:error, :forbidden} ->
        {:noreply, redirect_to_checkout(socket)}

      {:error, :insufficient_watch_time} ->
        {:noreply,
         put_flash(socket, :error, "Watch more of this lecture before marking it complete.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "We couldn't save your progress.")}
    end
  end

  defp put_preview_progress(socket, lecture_id, status, position_seconds) do
    update(socket, :preview_progress, fn preview_progress ->
      # Sticky completed — mirrors Learning.record_progress/3, so a late
      # video-progress tick can never un-complete a finished lecture.
      case Map.get(preview_progress, lecture_id) do
        %{status: :completed} ->
          preview_progress

        _ ->
          Map.put(preview_progress, lecture_id, %{
            status: status,
            last_position_seconds: position_seconds
          })
      end
    end)
  end

  @impl true
  def handle_info({event, _subject}, socket)
      when event in [:lecture_completed, :module_completed, :course_completed] do
    {:noreply, refresh_progress(socket)}
  end

  def handle_info({:certificate_ready, _certificate}, socket) do
    {:noreply,
     socket
     |> refresh_certificates()
     |> put_flash(:info, "Your certificate is ready to download.")}
  end

  @impl true
  def handle_async(
        {:generate_practice_questions, module_id},
        {:ok, {:ok, new_questions}},
        socket
      ) do
    course_id = socket.assigns.course.id
    practice_by_module = Assessments.published_practice_questions_by_module(course_id)

    current_module_id =
      if socket.assigns.current_practice_module do
        socket.assigns.current_practice_module.module.id
      end

    socket =
      socket
      |> assign(:generating_practice?, false)
      |> assign(:practice_by_module, practice_by_module)

    socket =
      if current_module_id == module_id do
        module = socket.assigns.current_practice_module.module
        questions = Map.get(practice_by_module, module_id, new_questions)
        assign(socket, :current_practice_module, %{module: module, questions: questions})
      else
        socket
      end

    {:noreply, put_flash(socket, :info, "Generated #{length(new_questions)} practice questions!")}
  end

  @impl true
  def handle_async(
        {:generate_practice_questions, _module_id},
        {:ok, {:error, _reason}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:generating_practice?, false)
     |> put_flash(:error, "Could not generate practice questions at this time.")}
  end

  @impl true
  def handle_async({:generate_practice_questions, _module_id}, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:generating_practice?, false)
     |> put_flash(:error, "Practice question generation timed out.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.student_layout active={:courses} current_user={@current_user}>
      <div id="course-player" class="py-8 lg:py-12">
        <div class="mx-auto max-w-container px-5 lg:px-8">
          <div
            :if={@preview?}
            id="admin-preview-banner"
            class="mb-6 flex flex-col items-start justify-between gap-3 rounded-2xl bg-ink px-5 py-3.5 text-white sm:flex-row sm:items-center sm:px-6"
          >
            <div class="flex flex-wrap items-center gap-3">
              <span class="inline-flex items-center gap-2 rounded-full bg-amber-500/20 px-3 py-1 text-xs font-semibold uppercase tracking-wider text-amber-400">
                <.icon name="hero-eye" class="h-4 w-4" /> Admin Preview Mode
              </span>
              <p class="text-sm font-medium text-white/90">
                You are viewing this course as a learner.
                <span class="text-white/60">— Progress & quiz scores will not be recorded.</span>
              </p>
            </div>
            <.link
              navigate={~p"/admin/courses/#{@course.slug}"}
              class="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-white/20 bg-white/10 px-3.5 py-1.5 text-xs font-semibold text-white transition hover:bg-white hover:text-ink"
            >
              <.icon name="hero-x-mark" class="h-4 w-4" /> Exit Preview
            </.link>
          </div>

          <div class="flex flex-col gap-6">
            <div class="flex items-center justify-between gap-4">
              <span class="rounded-full bg-mint px-3 py-1 text-xs font-medium uppercase tracking-wider text-primary">
                {if @preview?, do: "Preview", else: "Enrolled"}
              </span>
              <.link
                :if={!@preview?}
                navigate={~p"/courses-taken"}
                class="inline-flex items-center gap-1.5 text-sm font-medium text-muted transition hover:text-primary"
              >
                <.icon name="hero-arrow-left" class="h-4 w-4" /> My courses
              </.link>
            </div>

            <div class="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
              <h1 class="text-3xl font-semibold tracking-tight text-ink sm:text-4xl">
                {@course.title}
              </h1>
              <div class="w-full lg:w-72">
                <div class="flex items-center justify-between gap-4 text-sm">
                  <span class="text-muted">
                    {@course_progress.completed}/{@course_progress.total} lectures
                  </span>
                  <span id="course-progress-percent" class="font-semibold text-primary">
                    {@course_progress.percent}%
                  </span>
                </div>
                <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-mint">
                  <div
                    id="course-progress-bar"
                    class="h-full rounded-full bg-primary transition-all duration-500"
                    style={"width: #{@course_progress.percent}%"}
                  >
                  </div>
                </div>
              </div>
            </div>
          </div>

          <nav class="mt-8 flex flex-wrap gap-1.5 rounded-2xl bg-soft p-1.5">
            <button
              :for={{section, label, icon} <- section_nav_items()}
              type="button"
              phx-click="select-section"
              phx-value-section={section}
              class={[
                "inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-medium transition",
                @active_section == section && "bg-white text-primary shadow-sm",
                @active_section != section && "text-body hover:text-ink"
              ]}
            >
              <.icon name={icon} class="h-4 w-4" /> {label}
            </button>
            <.link
              :for={{mode, label, icon} <- study_hub_nav_items()}
              navigate={study_hub_path(@course, current_module(assigns), mode)}
              class="inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-medium text-body transition hover:text-ink"
            >
              <.icon name={icon} class="h-4 w-4" /> {label}
            </.link>
          </nav>

          <div
            :if={@active_section == :lessons}
            class="mt-6 grid items-start gap-8 lg:grid-cols-[minmax(0,1fr)_340px] lg:gap-12"
          >
            <section class="overflow-hidden rounded-3xl border border-black/5 bg-white">
              <%= if @current_quiz do %>
                <.quiz_taking_panel
                  current_quiz={@current_quiz}
                  quiz_result={@quiz_result}
                  quiz_answers={@quiz_answers}
                  current_question_index={@current_question_index}
                />
              <% else %>
                <%= if @current_practice_module do %>
                  <div class="p-8 lg:p-10">
                    <div class="flex flex-wrap items-center justify-between gap-4 border-b border-black/5 pb-6">
                      <div>
                        <span class="inline-flex items-center gap-2 rounded-full bg-mint px-3 py-1 text-xs font-semibold uppercase tracking-wider text-primary">
                          <.icon name="hero-beaker" class="h-4 w-4" /> Extra practice
                        </span>
                        <h2 class="mt-2 text-2xl font-semibold tracking-tight text-ink">
                          {@current_practice_module.module.title}
                        </h2>
                        <p class="mt-1 text-sm text-muted">
                          Low-stakes drill — doesn't count toward your certificate.
                        </p>
                      </div>
                      <button
                        :if={@current_practice_module.questions != []}
                        type="button"
                        phx-click="generate-practice-questions"
                        phx-value-module_id={@current_practice_module.module.id}
                        phx-disable-with="Generating questions..."
                        disabled={@generating_practice?}
                        class="inline-flex items-center gap-2 rounded-full bg-ink px-4 py-2 text-xs font-semibold text-white transition hover:bg-primary disabled:cursor-not-allowed disabled:opacity-50 active:scale-[0.96]"
                      >
                        <svg
                          :if={@generating_practice?}
                          class="h-3.5 w-3.5 animate-spin text-white"
                          xmlns="http://www.w3.org/2000/svg"
                          fill="none"
                          viewBox="0 0 24 24"
                        >
                          <circle
                            class="opacity-25"
                            cx="12"
                            cy="12"
                            r="10"
                            stroke="currentColor"
                            stroke-width="4"
                          >
                          </circle>
                          <path
                            class="opacity-75"
                            fill="currentColor"
                            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                          >
                          </path>
                        </svg>
                        {if @generating_practice?,
                          do: "Generating questions...",
                          else: "Generate extra questions"}
                      </button>
                    </div>

                    <div
                      :if={@current_practice_module.questions == []}
                      class="mt-8 rounded-3xl border border-dashed border-black/10 p-10 text-center"
                    >
                      <.icon name="hero-beaker" class="mx-auto h-10 w-10 text-primary/70" />
                      <h3 class="mt-3 text-lg font-semibold text-ink">No practice questions yet</h3>
                      <p class="mx-auto mt-1 max-w-md text-sm text-muted">
                        Quiz yourself! Generate a set of practice questions based on this module's lectures and resources.
                      </p>
                      <button
                        type="button"
                        phx-click="generate-practice-questions"
                        phx-value-module_id={@current_practice_module.module.id}
                        phx-disable-with="Generating questions..."
                        disabled={@generating_practice?}
                        class="mt-5 inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-ink disabled:cursor-not-allowed disabled:opacity-50 active:scale-[0.96]"
                      >
                        <svg
                          :if={@generating_practice?}
                          class="h-4 w-4 animate-spin text-white"
                          xmlns="http://www.w3.org/2000/svg"
                          fill="none"
                          viewBox="0 0 24 24"
                        >
                          <circle
                            class="opacity-25"
                            cx="12"
                            cy="12"
                            r="10"
                            stroke="currentColor"
                            stroke-width="4"
                          >
                          </circle>
                          <path
                            class="opacity-75"
                            fill="currentColor"
                            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                          >
                          </path>
                        </svg>
                        {if @generating_practice?,
                          do: "Generating questions...",
                          else: "Generate practice questions"}
                      </button>
                    </div>

                    <div :if={@current_practice_module.questions != []} class="mt-6 space-y-6">
                      <div
                        :for={
                          {question, idx} <- Enum.with_index(@current_practice_module.questions, 1)
                        }
                        class="rounded-2xl border border-black/5 p-5"
                      >
                        <% answer = Map.get(@practice_answers, to_string(question.id)) %>
                        <p class="text-xs font-semibold uppercase tracking-wider text-muted">
                          Question {idx}
                        </p>
                        <p class="mt-2 text-sm font-medium text-ink">{question.prompt}</p>

                        <div class="mt-4 space-y-2">
                          <div :for={option <- question.practice_question_options}>
                            <% answered? = answer != nil
                            selected? = answer && answer.option_id == to_string(option.id)

                            opt_class =
                              cond do
                                !answered? ->
                                  "border-black/10 text-body hover:border-primary/40 hover:bg-mint/40 cursor-pointer"

                                selected? && answer.correct? ->
                                  "border-green-300 bg-green-50 text-green-800 font-medium"

                                selected? && !answer.correct? ->
                                  "border-red-300 bg-red-50 text-red-700 font-medium"

                                option.correct && answered? ->
                                  "border-green-200 bg-green-50/60 text-green-700"

                                true ->
                                  "border-black/5 text-muted/60"
                              end %>
                            <button
                              type="button"
                              phx-click={if !answered?, do: "submit-practice-answer"}
                              phx-value-question-id={question.id}
                              phx-value-option-id={option.id}
                              disabled={answered?}
                              class={"flex w-full items-center gap-3 rounded-xl border px-4 py-3 text-left text-sm transition #{opt_class}"}
                            >
                              <span :if={selected? && answer.correct?}>
                                <.icon
                                  name="hero-check-circle"
                                  class="h-4 w-4 text-green-600 shrink-0"
                                />
                              </span>
                              <span :if={selected? && !answer.correct?}>
                                <.icon name="hero-x-circle" class="h-4 w-4 text-red-500 shrink-0" />
                              </span>
                              <span :if={option.correct && answered? && !selected?}>
                                <.icon
                                  name="hero-check-circle"
                                  class="h-4 w-4 text-green-500 shrink-0"
                                />
                              </span>
                              {option.label}
                            </button>
                          </div>
                        </div>

                        <p
                          :if={answer && question.explanation && question.explanation != ""}
                          class="mt-3 text-xs text-body/70 italic"
                        >
                          {question.explanation}
                        </p>
                      </div>
                    </div>
                  </div>
                <% else %>
                  <%= if @current_lecture do %>
                    <div :if={@current_lecture.duration_seconds} class="flex justify-center p-3">
                      <div
                        id={"protected-player-#{@current_lecture.id}"}
                        phx-hook="ProtectedVideo"
                        phx-update="ignore"
                        data-playback-url={playback_url_path(@current_lecture.id, @preview?)}
                        data-video-title={@current_lecture.title}
                        data-viewer-id={@current_user.id}
                        data-lecture-id={@current_lecture.id}
                        data-start-position={progress_position(@progress, @current_lecture.id)}
                        class="relative aspect-video w-full overflow-hidden rounded-2xl bg-black"
                        oncontextmenu="return false"
                      >
                        <div
                          data-role="player"
                          class="absolute inset-0 grid place-items-center text-sm text-white/70"
                        >
                          Loading protected video…
                        </div>
                        <div
                          :if={!@preview?}
                          data-role="watermark"
                          class="pointer-events-none absolute left-[6%] top-[8%] z-20 max-w-[80%] select-none rounded-full bg-black/30 px-3 py-1 text-xs font-medium text-white/60 backdrop-blur-sm transition-all duration-1000"
                        >
                          {@current_user.email}
                        </div>
                      </div>
                    </div>
                    <div class="bg-white p-8 lg:p-10">
                      <p class="text-xs font-medium uppercase tracking-widest text-primary">
                        Now playing
                      </p>
                      <h2 class="mt-3 text-2xl font-semibold tracking-tight text-ink">
                        {@current_lecture.title}
                      </h2>
                      <p class="mt-3 max-w-2xl leading-relaxed text-body">
                        {@current_lecture.description}
                      </p>

                      <% watched_enough? =
                        is_nil(@current_lecture.duration_seconds) or
                          Learning.watched_enough?(
                            progress_position(@progress, @current_lecture.id),
                            @current_lecture.duration_seconds
                          ) %>
                      <div class="mt-8 flex flex-wrap items-center gap-3">
                        <button
                          :if={progress_status(@progress, @current_lecture.id) != :completed}
                          id="mark-lecture-complete"
                          type="button"
                          phx-click="complete-lecture"
                          phx-value-lecture_id={@current_lecture.id}
                          disabled={!watched_enough?}
                          title={
                            if !watched_enough?,
                              do: "Watch at least 80% of this lecture to unlock this button."
                          }
                          class="rounded-full bg-primary px-5 py-2.5 text-sm font-medium text-white transition hover:bg-ink disabled:cursor-not-allowed disabled:opacity-40"
                        >
                          Mark complete
                        </button>
                        <span
                          :if={progress_status(@progress, @current_lecture.id) == :completed}
                          class="inline-flex items-center gap-2 rounded-full bg-mint px-4 py-2 text-sm font-medium text-primary"
                        >
                          <.icon name="hero-check-circle" class="h-5 w-5" /> Completed
                        </span>
                      </div>
                      <p
                        :if={
                          progress_status(@progress, @current_lecture.id) != :completed &&
                            !watched_enough?
                        }
                        class="mt-2 text-xs text-muted"
                      >
                        Watch at least 80% of this lecture to unlock this button.
                      </p>
                    </div>

                    <div
                      :if={@current_lecture.resources != []}
                      id="lecture-resources"
                      class="border-t border-black/5 bg-white p-8 lg:p-10"
                    >
                      <h3 class="text-xs font-medium uppercase tracking-widest text-muted">
                        Resources
                      </h3>
                      <ul class="mt-4 space-y-2.5">
                        <li :for={resource <- @current_lecture.resources}>
                          <.link
                            href={resource_download_path(resource.id, @preview?)}
                            target={if resource.kind == :link, do: "_blank"}
                            class="flex items-center gap-3 rounded-xl border border-black/5 px-4 py-3 text-sm text-body transition hover:border-primary/40 hover:bg-mint/40 hover:text-ink"
                          >
                            <span class="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-mint text-primary">
                              <.icon name={resource_icon(resource.kind)} class="h-4 w-4" />
                            </span>
                            <span class="min-w-0 flex-1 truncate font-medium">{resource.name}</span>
                            <.icon
                              name={
                                if resource.kind == :link,
                                  do: "hero-arrow-top-right-on-square",
                                  else: "hero-arrow-down-tray"
                              }
                              class="h-4 w-4 shrink-0 text-muted"
                            />
                          </.link>
                        </li>
                      </ul>
                    </div>

                    <div
                      :if={@current_lecture.questions != []}
                      id="lecture-faq"
                      class="border-t border-black/5 bg-white p-8 lg:p-10"
                    >
                      <h3 class="text-xs font-medium uppercase tracking-widest text-muted">
                        Practice questions
                      </h3>
                      <p class="mt-1 text-xs text-muted">
                        Type your answer and submit — you'll get instant feedback.
                      </p>
                      <div class="mt-4 space-y-4">
                        <%= for question <- @current_lecture.questions do %>
                          <% submission = Map.get(@lq_submissions, question.id) %>
                          <div class="rounded-2xl border border-black/5 p-5">
                            <p class="text-sm font-medium text-ink">{question.question}</p>
                            <%= if submission do %>
                              <% band = lq_feedback_band(submission.similarity_score) %>
                              <div class={[
                                "mt-3 rounded-xl px-4 py-3 text-sm font-medium",
                                band.class
                              ]}>
                                {band.label}
                              </div>
                              <p
                                :if={submission.similarity_score < 0.5}
                                class="mt-3 text-sm text-body"
                              >
                                <span class="font-medium text-ink">Model answer:</span>
                                {question.answer}
                              </p>
                            <% else %>
                              <form phx-submit="submit-lecture-question" class="mt-3 space-y-2">
                                <input type="hidden" name="question-id" value={question.id} />
                                <textarea
                                  name="answer"
                                  rows="3"
                                  placeholder="Type your answer here…"
                                  required
                                  class="block w-full rounded-xl border border-black/10 bg-soft px-4 py-2.5 text-sm text-ink placeholder-muted focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
                                ></textarea>
                                <button
                                  type="submit"
                                  class="rounded-full bg-primary px-5 py-2 text-sm font-semibold text-white transition hover:bg-ink"
                                >
                                  Submit answer
                                </button>
                              </form>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% else %>
                    <div class="grid min-h-80 place-items-center bg-white p-8 text-center text-muted">
                      This course does not have any content selected.
                    </div>
                  <% end %>
                <% end %>
              <% end %>
            </section>

            <aside class="flex max-h-[calc(100vh-2rem)] flex-col rounded-3xl bg-white p-6 lg:sticky lg:top-4 lg:p-7">
              <h2 class="text-xs font-medium uppercase tracking-widest text-muted">Course content</h2>
              <div class="-mr-3 mt-6 space-y-8 overflow-y-auto pr-3">
                <section :for={module <- @course.modules}>
                  <h3 class="px-1 text-sm font-semibold text-ink">
                    {module.position}. {module.title}
                  </h3>
                  <div class="mt-3 space-y-0.5">
                    <button
                      :for={lecture <- module.lectures}
                      type="button"
                      phx-click="select-lecture"
                      phx-value-id={lecture.id}
                      disabled={!lecture_unlocked?(@unlocked_lecture_ids, lecture.id)}
                      data-lecture-id={lecture.id}
                      data-locked={
                        if lecture_unlocked?(@unlocked_lecture_ids, lecture.id),
                          do: "false",
                          else: "true"
                      }
                      class={[
                        "flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left text-sm transition",
                        @current_lecture && @current_lecture.id == lecture.id &&
                          "bg-mint font-medium text-primary",
                        (!@current_lecture || @current_lecture.id != lecture.id) &&
                          lecture_unlocked?(@unlocked_lecture_ids, lecture.id) &&
                          "text-body hover:bg-soft hover:text-ink",
                        !lecture_unlocked?(@unlocked_lecture_ids, lecture.id) &&
                          "cursor-not-allowed text-muted"
                      ]}
                    >
                      <span class={[
                        "grid h-6 w-6 shrink-0 place-items-center rounded-full text-xs font-semibold",
                        progress_status(@progress, lecture.id) == :completed &&
                          "bg-primary text-white",
                        progress_status(@progress, lecture.id) != :completed &&
                          lecture_unlocked?(@unlocked_lecture_ids, lecture.id) &&
                          "bg-mint text-primary",
                        !lecture_unlocked?(@unlocked_lecture_ids, lecture.id) && "text-muted/60"
                      ]}>
                        <.icon
                          :if={progress_status(@progress, lecture.id) == :completed}
                          name="hero-check"
                          class="h-3.5 w-3.5"
                        />
                        <.icon
                          :if={!lecture_unlocked?(@unlocked_lecture_ids, lecture.id)}
                          name="hero-lock-closed"
                          class="h-3.5 w-3.5"
                        />
                        <span :if={
                          lecture_unlocked?(@unlocked_lecture_ids, lecture.id) &&
                            progress_status(@progress, lecture.id) != :completed
                        }>
                          {lecture.position}
                        </span>
                      </span>
                      <span class="min-w-0 flex-1">
                        <span class="block truncate">{lecture.title}</span>
                        <span
                          :if={progress_status(@progress, lecture.id) == :in_progress}
                          class="mt-0.5 block text-xs text-muted"
                        >
                          {progress_percent(@progress, lecture)}% watched
                        </span>
                      </span>
                    </button>

                    <% quiz_unlocked? = module_quiz_unlocked?(module, @progress, @preview?) %>
                    <button
                      :if={module_quiz = Map.get(@quizzes_by_module, module.id)}
                      type="button"
                      phx-click="select-quiz"
                      phx-value-module_id={module.id}
                      disabled={!quiz_unlocked?}
                      data-locked={if quiz_unlocked?, do: "false", else: "true"}
                      class={[
                        "mt-1 flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left text-sm transition",
                        @current_quiz && @current_quiz.quiz.id == module_quiz.id &&
                          "bg-mint font-medium text-primary",
                        (!@current_quiz || @current_quiz.quiz.id != module_quiz.id) &&
                          quiz_unlocked? &&
                          "text-body hover:bg-soft hover:text-ink",
                        !quiz_unlocked? && "cursor-not-allowed text-muted"
                      ]}
                    >
                      <span class={[
                        "grid h-6 w-6 shrink-0 place-items-center rounded-full text-xs font-semibold",
                        quiz_unlocked? && "bg-mint text-primary",
                        !quiz_unlocked? && "text-muted/60"
                      ]}>
                        <.icon :if={quiz_unlocked?} name="hero-academic-cap" class="h-3.5 w-3.5" />
                        <.icon :if={!quiz_unlocked?} name="hero-lock-closed" class="h-3.5 w-3.5" />
                      </span>
                      <span class="min-w-0 flex-1">
                        <span class="block font-medium truncate">Module {module.position} Quiz</span>
                      </span>
                    </button>

                    <% practice_unlocked? =
                      practice_questions_unlocked?(
                        module,
                        @quizzes_by_module,
                        @completed_quiz_ids,
                        @progress,
                        @preview?
                      ) %>
                    <button
                      type="button"
                      phx-click="start-practice"
                      phx-value-module_id={module.id}
                      disabled={!practice_unlocked?}
                      data-locked={if practice_unlocked?, do: "false", else: "true"}
                      class={[
                        "mt-1 flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left text-sm transition",
                        @current_practice_module &&
                          @current_practice_module.module.id == module.id &&
                          "bg-mint font-medium text-primary",
                        (!@current_practice_module ||
                           @current_practice_module.module.id != module.id) &&
                          practice_unlocked? &&
                          "text-body hover:bg-soft hover:text-ink",
                        !practice_unlocked? && "cursor-not-allowed text-muted"
                      ]}
                    >
                      <span class={[
                        "grid h-6 w-6 shrink-0 place-items-center rounded-full text-xs font-semibold",
                        practice_unlocked? && "bg-mint text-primary",
                        !practice_unlocked? && "text-muted/60"
                      ]}>
                        <.icon :if={practice_unlocked?} name="hero-beaker" class="h-3.5 w-3.5" />
                        <.icon :if={!practice_unlocked?} name="hero-lock-closed" class="h-3.5 w-3.5" />
                      </span>
                      <span class="min-w-0 flex-1">
                        <span class="block font-medium truncate">Extra practice questions</span>
                      </span>
                    </button>
                  </div>
                </section>
              </div>
            </aside>
          </div>

          <section
            :if={@active_section == :module_quiz}
            class="mt-6 overflow-hidden rounded-3xl border border-black/5 bg-white"
          >
            <%= if @current_quiz do %>
              <div class="flex items-center justify-between gap-4 border-b border-black/5 px-8 pt-6 lg:px-10">
                <button
                  :if={length(@course.modules) > 1}
                  type="button"
                  phx-click="exit-quiz"
                  class="inline-flex items-center gap-1.5 text-sm font-medium text-muted transition hover:text-primary"
                >
                  <.icon name="hero-arrow-left" class="h-4 w-4" /> Choose a different module
                </button>
              </div>
              <.quiz_taking_panel
                current_quiz={@current_quiz}
                quiz_result={@quiz_result}
                quiz_answers={@quiz_answers}
                current_question_index={@current_question_index}
              />
            <% else %>
              <div class="p-8 lg:p-10">
                <span class="inline-flex items-center gap-2 rounded-full bg-mint px-3 py-1 text-xs font-semibold uppercase tracking-wider text-primary">
                  <.icon name="hero-academic-cap" class="h-4 w-4" /> Module Quiz
                </span>
                <h2 class="mt-3 text-2xl font-semibold tracking-tight text-ink">
                  Choose a module to take its quiz
                </h2>
                <p class="mt-2 text-body">
                  Each module quiz covers everything in that module's lessons.
                </p>

                <div class="mt-6 grid gap-3 sm:grid-cols-2">
                  <%= for module <- @course.modules do %>
                    <% module_quiz = Map.get(@quizzes_by_module, module.id) %>
                    <% unlocked? = module_quiz_unlocked?(module, @progress, @preview?) %>
                    <button
                      type="button"
                      phx-click="select-quiz"
                      phx-value-module_id={module.id}
                      disabled={!module_quiz || !unlocked?}
                      class={[
                        "flex items-center justify-between gap-3 rounded-2xl border p-4 text-left text-sm transition",
                        module_quiz && unlocked? &&
                          "border-black/10 text-body hover:border-primary/40 hover:bg-mint/40 hover:text-ink",
                        (!module_quiz || !unlocked?) &&
                          "cursor-not-allowed border-black/5 text-muted"
                      ]}
                    >
                      <span class="min-w-0">
                        <span class="block truncate font-medium text-ink">
                          Module {module.position}: {module.title}
                        </span>
                        <span class="mt-0.5 block text-xs text-muted">
                          <%= cond do %>
                            <% !module_quiz -> %>
                              No quiz available yet
                            <% !unlocked? -> %>
                              Locked — finish this module's lessons first
                            <% true -> %>
                              {length(module.lectures)} lectures covered
                          <% end %>
                        </span>
                      </span>
                      <.icon
                        :if={!module_quiz || !unlocked?}
                        name="hero-lock-closed"
                        class="h-4 w-4 shrink-0"
                      />
                      <.icon
                        :if={module_quiz && unlocked?}
                        name="hero-arrow-right"
                        class="h-4 w-4 shrink-0 text-primary"
                      />
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>
          </section>

          <section
            :if={!@preview?}
            id="course-certificates"
            class="mt-8 rounded-3xl border border-black/5 bg-white p-6 lg:p-8"
          >
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div>
                <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                  Achievements
                </span>
                <h2 class="mt-4 text-2xl font-semibold text-ink">Your certificates</h2>
                <p class="mt-2 text-body">
                  Module certificates appear as each module is completed. Your course certificate
                  appears after every lecture is complete.
                </p>
              </div>
              <span
                :if={@course_progress.complete? && !course_certificate?(@certificates)}
                id="course-certificate-pending"
                class="rounded-full border border-black/10 px-4 py-2 text-sm font-medium text-body"
              >
                Preparing course certificate…
              </span>
            </div>

            <div :if={@certificates != []} class="mt-6 grid gap-4 md:grid-cols-2">
              <article
                :for={certificate <- @certificates}
                id={"certificate-#{certificate.id}"}
                class="flex items-center justify-between gap-4 rounded-2xl border border-black/5 bg-soft p-5"
              >
                <div class="min-w-0">
                  <p class="text-xs font-semibold uppercase tracking-wider text-primary">
                    {if certificate.type == :module,
                      do: "Module certificate",
                      else: "Course certificate"}
                  </p>
                  <h3 class="mt-1 truncate font-medium text-ink">
                    {certificate_title(certificate)}
                  </h3>
                  <p class="mt-1 text-xs text-muted">{certificate.serial_number}</p>
                </div>
                <.link
                  href={~p"/certificates/#{certificate.id}/download"}
                  class="inline-flex shrink-0 items-center gap-2 rounded-full bg-ink px-4 py-2 text-sm font-medium text-white transition hover:bg-primary"
                >
                  <.icon name="hero-arrow-down-tray" class="h-4 w-4" /> Download
                </.link>
              </article>
            </div>

            <p
              :if={@certificates == [] && !@course_progress.complete?}
              class="mt-6 rounded-2xl bg-mint p-5 text-sm text-body"
            >
              Complete your first module to earn your first certificate.
            </p>
          </section>
        </div>
      </div>
    </.student_layout>
    """
  end

  defp section_nav_items do
    [
      {:lessons, "Lessons", "hero-play-circle"},
      {:module_quiz, "Module quiz", "hero-academic-cap"}
    ]
  end

  # Flashcards/Extra practice/Timed quiz moved to the cross-course
  # `WasomiWeb.StudyHubLive` — these render as plain navigation links here,
  # not `@active_section` tabs, pre-scoped to whatever module the learner is
  # currently watching so switching to self-study tools for "this" module
  # stays one click away.
  defp study_hub_nav_items do
    [
      {"flashcards", "Flashcards", "hero-rectangle-stack"},
      {"practice", "Extra practice", "hero-pencil-square"},
      {"timed_quiz", "Timed quiz", "hero-clock"}
    ]
  end

  defp current_module(%{current_lecture: nil}), do: nil

  defp current_module(%{current_lecture: lecture, course: course}) do
    Enum.find(course.modules, &(&1.id == lecture.module_id))
  end

  defp study_hub_path(course, nil, _mode), do: ~p"/learn/study?#{%{course: course.slug}}"

  defp study_hub_path(course, module, mode) do
    ~p"/learn/study?#{%{course: course.slug, module: module.id, scope: "module", mode: mode}}"
  end

  defp lecture_page_title(socket, lecture),
    do: "#{lecture.title} · #{preview_page_title(socket.assigns.course, socket.assigns.preview?)}"

  defp refresh_progress(socket) do
    course = socket.assigns.course
    lectures = course_lectures(course)
    preview? = socket.assigns.preview?

    progress =
      if preview? do
        socket.assigns.preview_progress
      else
        Learning.progress_for_course(socket.assigns.current_user, course)
      end

    course_progress = Learning.summarize_progress(course, progress)
    unlocked_lecture_ids = unlocked_lecture_ids(lectures, progress, preview?)
    current_lecture = pick_current_lecture(socket, lectures, progress)

    socket
    |> assign(:course_progress, course_progress)
    |> assign(:progress, progress)
    |> assign(:unlocked_lecture_ids, unlocked_lecture_ids)
    |> assign(:current_lecture, current_lecture)
    |> refresh_certificates()
  end

  defp pick_current_lecture(socket, lectures, progress) do
    socket.assigns[:current_lecture] ||
      Enum.find(lectures, &(progress_status(progress, &1.id) != :completed)) ||
      List.last(lectures)
  end

  defp refresh_certificates(socket) do
    certificates =
      if socket.assigns.preview? do
        []
      else
        Certificates.list_for_user_course(socket.assigns.current_user, socket.assigns.course)
      end

    assign(socket, :certificates, certificates)
  end

  defp redirect_to_checkout(socket) do
    socket
    |> put_flash(:error, "Your enrollment is no longer active.")
    |> redirect(to: ~p"/courses/#{socket.assigns.course.slug}/checkout")
  end

  defp current_lecture(socket, lecture_id) do
    case socket.assigns.current_lecture do
      %{id: id} = lecture ->
        if to_string(id) == to_string(lecture_id), do: lecture

      _ ->
        nil
    end
  end

  defp find_lecture(course, id) do
    Enum.find(course_lectures(course), &(to_string(&1.id) == id))
  end

  defp course_lectures(course), do: Enum.flat_map(course.modules, & &1.lectures)

  # Admins previewing content just want to sanity-check it, not re-earn
  # access to it lecture by lecture — every lecture and quiz is unlocked
  # unconditionally in preview mode, independent of (unpersisted) preview
  # progress. Real learners keep the sequential gate untouched below.
  defp unlocked_lecture_ids(lectures, _progress, true = _preview?),
    do: MapSet.new(lectures, & &1.id)

  defp unlocked_lecture_ids(lectures, progress, false = _preview?) do
    Enum.reduce_while(lectures, MapSet.new(), fn lecture, unlocked ->
      unlocked = MapSet.put(unlocked, lecture.id)

      if progress_status(progress, lecture.id) == :completed do
        {:cont, unlocked}
      else
        {:halt, unlocked}
      end
    end)
  end

  defp lecture_unlocked?(unlocked_lecture_ids, lecture_id),
    do: MapSet.member?(unlocked_lecture_ids, lecture_id)

  defp module_quiz_unlocked?(_module, _progress, true = _preview?), do: true

  defp module_quiz_unlocked?(module, progress, false = _preview?) do
    module.lectures != [] and
      Enum.all?(module.lectures, &(progress_status(progress, &1.id) == :completed))
  end

  defp practice_questions_unlocked?(
         _module,
         _quizzes_by_module,
         _completed_quiz_ids,
         _progress,
         true = _preview?
       ),
       do: true

  defp practice_questions_unlocked?(
         module,
         quizzes_by_module,
         completed_quiz_ids,
         progress,
         false = _preview?
       ) do
    case Map.get(quizzes_by_module, module.id) do
      %{id: quiz_id} ->
        MapSet.member?(completed_quiz_ids, quiz_id)

      nil ->
        module_quiz_unlocked?(module, progress, false)
    end
  end

  defp progress_status(progress, lecture_id) do
    case progress[lecture_id] do
      %{status: status} -> status
      nil -> :not_started
    end
  end

  defp progress_position(progress, lecture_id) do
    case progress[lecture_id] do
      %{last_position_seconds: position} -> position
      nil -> 0
    end
  end

  defp progress_percent(progress, lecture) do
    progress
    |> progress_position(lecture.id)
    |> Kernel./(lecture.duration_seconds)
    |> Kernel.*(100)
    |> round()
    |> min(100)
  end

  defp course_certificate?(certificates),
    do: Enum.any?(certificates, &(&1.type == :course))

  defp certificate_title(%{type: :module, module: module}), do: module.title
  defp certificate_title(%{type: :course, course: course}), do: course.title

  defp load_lq_submissions(socket, lecture) do
    if socket.assigns.preview? do
      %{}
    else
      Catalog.map_lecture_question_submissions(socket.assigns.current_user, lecture)
    end
  end

  defp lq_feedback_band(score) when score >= 0.8,
    do: %{label: "Great answer!", class: "bg-green-50 text-green-700"}

  defp lq_feedback_band(score) when score >= 0.5,
    do: %{label: "Close enough — good thinking!", class: "bg-amber-50 text-amber-700"}

  defp lq_feedback_band(_score),
    do: %{label: "Needs work — see the model answer below.", class: "bg-red-50 text-red-700"}
end
