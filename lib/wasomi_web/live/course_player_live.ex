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

        {:ok,
         socket
         |> assign(:page_title, preview_page_title(course, preview?))
         |> assign(:course, course)
         |> assign(:quizzes_by_module, quizzes_by_module)
         |> assign(:current_quiz, nil)
         |> assign(:quiz_answers, %{})
         |> assign(:quiz_result, nil)
         |> assign(:current_question_index, 0)
         |> assign(:preview?, preview?)
         |> assign(:preview_progress, %{})
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

  @impl true
  def handle_event("select-lecture", %{"id" => id}, socket) do
    lecture = find_lecture(socket.assigns.course, id)

    if lecture && lecture_unlocked?(socket.assigns.unlocked_lecture_ids, lecture.id) do
      {:noreply,
       socket
       |> assign(:current_quiz, nil)
       |> assign(:quiz_result, nil)
       |> assign(:current_lecture, lecture)
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

              {:noreply,
               socket
               |> assign(:current_lecture, nil)
               |> assign(:current_quiz, %{quiz: quiz, module: module, questions: questions})
               |> assign(:quiz_answers, %{})
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
          normalized = Map.new(answers, fn {k, v} -> {to_string(k), to_string(v)} end)

          correct_count =
            Enum.count(questions, fn q ->
              selected = Map.get(normalized, to_string(q.id))

              Enum.any?(
                q.question_options,
                &(to_string(&1.id) == selected and &1.correct)
              )
            end)

          score_percent =
            if questions != [], do: round(correct_count / length(questions) * 100), else: 0

          passed = score_percent >= quiz.passing_score_percent

          result = %{
            score_percent: score_percent,
            passed: passed,
            preview?: true,
            correct_count: correct_count,
            total_count: length(questions)
          }

          {:noreply, assign(socket, :quiz_result, result)}
        else
          case Assessments.submit_quiz(socket.assigns.current_user, quiz, answers) do
            {:ok, submission} ->
              {:noreply,
               socket
               |> assign(:quiz_result, submission)
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
          not Learning.watched_enough?(
            progress_position(socket.assigns.progress, lecture.id),
            lecture.duration_seconds
          ) ->
            {:noreply,
             put_flash(socket, :error, "Watch more of this lecture before marking it complete.")}

          socket.assigns.preview? ->
            {:noreply,
             socket
             |> put_preview_progress(lecture.id, :completed, lecture.duration_seconds)
             |> refresh_progress()
             |> put_flash(:info, "Lecture marked complete — preview only, nothing was saved.")}

          true ->
            persist_progress(socket, lecture, lecture.duration_seconds, true)
        end
    end
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
  def render(assigns) do
    ~H"""
    <.student_layout active={:courses} current_user={@current_user}>
      <div id="course-player" class="py-8 lg:py-12">
        <div class="mx-auto max-w-container px-5 lg:px-8">
          <div
            :if={@preview?}
            id="admin-preview-banner"
            class="mb-6 flex flex-col items-start justify-between gap-3 rounded-2xl bg-dark px-5 py-3.5 text-white sm:flex-row sm:items-center sm:px-6"
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
              class="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-white/20 bg-white/10 px-3.5 py-1.5 text-xs font-semibold text-white transition hover:bg-white hover:text-dark"
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
              <h1 class="text-3xl font-semibold tracking-tight text-dark sm:text-4xl">
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

          <div class="mt-10 grid items-start gap-8 lg:grid-cols-[minmax(0,1fr)_340px] lg:gap-12">
            <section class="overflow-hidden rounded-3xl border border-black/5 bg-white">
              <%= if @current_quiz do %>
                <div class="p-8 lg:p-10">
                  <div class="flex flex-wrap items-center justify-between gap-4 border-b border-black/5 pb-6">
                    <div>
                      <span class="inline-flex items-center gap-2 rounded-full bg-mint px-3 py-1 text-xs font-semibold uppercase tracking-wider text-primary">
                        <.icon name="hero-academic-cap" class="h-4 w-4" />
                        Module {@current_quiz.module.position} Quiz
                      </span>
                      <h2 class="mt-2 text-2xl font-semibold tracking-tight text-dark">
                        {@current_quiz.module.title}
                      </h2>
                      <p class="mt-1 text-sm text-muted">
                        Passing requirement:
                        <span class="font-semibold text-primary">
                          {@current_quiz.quiz.passing_score_percent}% score
                        </span>
                      </p>
                    </div>
                  </div>

                  <%= if @quiz_result do %>
                    <div class={[
                      "mt-8 rounded-2xl p-6 text-center sm:p-8",
                      if(result_passed?(@quiz_result), do: "bg-mint", else: "bg-red-50")
                    ]}>
                      <div class={[
                        "mx-auto flex h-16 w-16 items-center justify-center rounded-full",
                        if(result_passed?(@quiz_result),
                          do: "bg-white text-primary",
                          else: "bg-white text-red-600"
                        )
                      ]}>
                        <.icon
                          name={
                            if(result_passed?(@quiz_result),
                              do: "hero-check-circle",
                              else: "hero-x-circle"
                            )
                          }
                          class="h-8 w-8"
                        />
                      </div>

                      <h3 class="mt-4 text-2xl font-bold text-dark">
                        {if result_passed?(@quiz_result), do: "Quiz Passed!", else: "Quiz Not Passed"}
                      </h3>
                      <p class={[
                        "mt-2 text-3xl font-extrabold",
                        if(result_passed?(@quiz_result), do: "text-primary", else: "text-red-600")
                      ]}>
                        {result_score(@quiz_result)}%
                      </p>

                      <p :if={preview_result?(@quiz_result)} class="mt-3 text-xs text-muted">
                        Admin Preview Result — score was evaluated in-memory and not saved.
                      </p>

                      <div class="mt-6 flex justify-center gap-4">
                        <button
                          type="button"
                          phx-click="retake-quiz"
                          class="rounded-full border border-black/10 bg-white px-5 py-2.5 text-sm font-semibold text-dark transition hover:bg-dark hover:text-white"
                        >
                          Retake Quiz
                        </button>
                      </div>
                    </div>
                  <% else %>
                    <% question = Enum.at(@current_quiz.questions, @current_question_index) %>
                    <% total = length(@current_quiz.questions) %>
                    <% last_question? = @current_question_index == total - 1 %>
                    <form phx-submit="submit-quiz" class="mt-8 space-y-6">
                      <div class="h-1.5 overflow-hidden rounded-full bg-mint">
                        <div
                          class="h-full rounded-full bg-primary transition-all duration-300"
                          style={"width: #{round((@current_question_index + 1) / total * 100)}%"}
                        >
                        </div>
                      </div>

                      <div class="min-h-[480px] rounded-2xl border border-black/5 p-6">
                        <p class="text-xs font-semibold uppercase tracking-wider text-primary">
                          Question {@current_question_index + 1} of {total}
                        </p>
                        <h3 class="mt-2 text-lg font-medium leading-snug text-dark">
                          {question.prompt}
                        </h3>

                        <div class="mt-4 space-y-2.5">
                          <label
                            :for={option <- question.question_options}
                            class={[
                              "flex items-center gap-3 rounded-xl border p-3.5 transition cursor-pointer",
                              if(
                                to_string(Map.get(@quiz_answers, to_string(question.id))) ==
                                  to_string(option.id),
                                do: "border-primary bg-mint text-dark font-medium",
                                else:
                                  "border-black/10 text-body hover:border-primary/40 hover:bg-mint/40"
                              )
                            ]}
                          >
                            <input
                              type="radio"
                              name={"question_#{question.id}"}
                              value={option.id}
                              checked={
                                to_string(Map.get(@quiz_answers, to_string(question.id))) ==
                                  to_string(option.id)
                              }
                              phx-click="select-quiz-option"
                              phx-value-question-id={question.id}
                              phx-value-option-id={option.id}
                              class="h-4 w-4 border-black/20 bg-white text-primary focus:ring-primary"
                            />
                            <span class="text-sm">{option.label}</span>
                          </label>
                        </div>
                      </div>

                      <div class="flex items-center justify-between border-t border-black/5 pt-6">
                        <button
                          type="button"
                          phx-click="prev-question"
                          disabled={@current_question_index == 0}
                          class="inline-flex items-center gap-1.5 rounded-full border border-black/10 px-5 py-2.5 text-sm font-semibold text-dark transition hover:bg-mint disabled:cursor-not-allowed disabled:opacity-40"
                        >
                          <.icon name="hero-arrow-left" class="h-4 w-4" /> Back
                        </button>

                        <span class="text-xs text-muted">
                          Answered {map_size(@quiz_answers)} of {total} questions
                        </span>

                        <button
                          :if={!last_question?}
                          type="button"
                          phx-click="next-question"
                          class="inline-flex items-center gap-1.5 rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-white transition hover:bg-dark"
                        >
                          Next <.icon name="hero-arrow-right" class="h-4 w-4" />
                        </button>

                        <button
                          :if={last_question?}
                          type="submit"
                          disabled={map_size(@quiz_answers) < total}
                          class="rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-white transition hover:bg-dark disabled:cursor-not-allowed disabled:opacity-40"
                        >
                          Submit Quiz
                        </button>
                      </div>
                    </form>
                  <% end %>
                </div>
              <% else %>
                <%= if @current_lecture do %>
                  <div class="flex justify-center p-3">
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
                    <h2 class="mt-3 text-2xl font-semibold tracking-tight text-dark">
                      {@current_lecture.title}
                    </h2>
                    <p class="mt-3 max-w-2xl leading-relaxed text-body">
                      {@current_lecture.description}
                    </p>

                    <% watched_enough? =
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
                        class="rounded-full bg-primary px-5 py-2.5 text-sm font-medium text-white transition hover:bg-dark disabled:cursor-not-allowed disabled:opacity-40"
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
                          class="flex items-center gap-3 rounded-xl border border-black/5 px-4 py-3 text-sm text-body transition hover:border-primary/40 hover:bg-mint/40 hover:text-dark"
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
                      Common learner questions
                    </h3>
                    <div class="mt-4 space-y-3">
                      <details
                        :for={question <- @current_lecture.questions}
                        class="group rounded-2xl border border-black/5 px-5 [&_summary::-webkit-details-marker]:hidden"
                      >
                        <summary class="flex cursor-pointer list-none items-center justify-between gap-3 py-4 text-sm font-medium text-dark">
                          {question.question}
                          <.icon
                            name="hero-plus"
                            class="h-4 w-4 shrink-0 text-primary transition group-open:rotate-45"
                          />
                        </summary>
                        <p class="pb-4 text-sm text-body">{question.answer}</p>
                      </details>
                    </div>
                  </div>
                <% else %>
                  <div class="grid min-h-80 place-items-center bg-white p-8 text-center text-muted">
                    This course does not have any content selected.
                  </div>
                <% end %>
              <% end %>
            </section>

            <aside class="flex max-h-[calc(100vh-2rem)] flex-col rounded-3xl bg-white p-6 lg:sticky lg:top-4 lg:p-7">
              <h2 class="text-xs font-medium uppercase tracking-widest text-muted">Course content</h2>
              <div class="-mr-3 mt-6 space-y-8 overflow-y-auto pr-3">
                <section :for={module <- @course.modules}>
                  <h3 class="px-1 text-sm font-semibold text-dark">
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
                          "text-body hover:bg-soft hover:text-dark",
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
                          "text-body hover:bg-soft hover:text-dark",
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
                  </div>
                </section>
              </div>
            </aside>
          </div>

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
                <h2 class="mt-4 text-2xl font-semibold text-dark">Your certificates</h2>
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
                  <h3 class="mt-1 truncate font-medium text-dark">
                    {certificate_title(certificate)}
                  </h3>
                  <p class="mt-1 text-xs text-muted">{certificate.serial_number}</p>
                </div>
                <.link
                  href={~p"/certificates/#{certificate.id}/download"}
                  class="inline-flex shrink-0 items-center gap-2 rounded-full bg-dark px-4 py-2 text-sm font-medium text-white transition hover:bg-primary"
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

  defp result_passed?(%{passed: passed}), do: passed
  defp result_passed?(%Wasomi.Assessments.QuizSubmission{passed: passed}), do: passed
  defp result_passed?(_), do: false

  defp result_score(%{score_percent: score}), do: score
  defp result_score(%Wasomi.Assessments.QuizSubmission{score_percent: score}), do: score
  defp result_score(_), do: 0

  defp preview_result?(%{preview?: preview?}), do: preview?
  defp preview_result?(%Wasomi.Assessments.QuizSubmission{}), do: false
  defp preview_result?(_), do: false
end
