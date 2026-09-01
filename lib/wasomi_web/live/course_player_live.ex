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

  alias Wasomi.{Assessments, Catalog, Certificates, Channels, Enrollments, Learning, Reviews}

  require Logger

  import WasomiWeb.StudyComponents, only: [quiz_taking_panel: 1]
  import WasomiWeb.CaptureProtection, only: [capture_guard_attrs: 1, watermark_text: 1]

  @impl true
  def mount(%{"slug" => slug} = params, _session, socket) do
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
        channel = Channels.get_or_create_for_course(course)

        if connected?(socket) do
          Channels.subscribe(channel)

          unless preview? do
            Learning.subscribe(socket.assigns.current_user)
            Certificates.subscribe(socket.assigns.current_user)
          end
        end

        initial_section =
          if params["tab"] == "discussion", do: :discussion, else: :lessons

        channel_highlight_message_id = params["msg"]

        if connected?(socket) and initial_section == :discussion and not preview? do
          Channels.mark_read(socket.assigns.current_user, channel)
        end

        channel_unread =
          if preview? or initial_section == :discussion,
            do: 0,
            else: Channels.unread_count(socket.assigns.current_user, channel)

        quizzes_by_module = Assessments.get_quizzes_by_module(course.id)

        completed_quiz_ids =
          if preview? do
            MapSet.new()
          else
            Assessments.completed_quiz_ids_for_user(socket.assigns.current_user.id, course.id)
          end

        course_review =
          if preview? do
            nil
          else
            Reviews.get_user_course_review(socket.assigns.current_user, course)
          end

        {:ok,
         socket
         |> assign(:page_title, preview_page_title(course, preview?))
         |> assign(:course, course)
         |> assign(:quizzes_by_module, quizzes_by_module)
         |> assign(:completed_quiz_ids, completed_quiz_ids)
         |> assign(:current_quiz, nil)
         |> assign(:quiz_answers, %{})
         |> assign(:quiz_result, nil)
         |> assign(:current_question_index, 0)
         |> assign(:active_section, initial_section)
         |> assign(:channel, channel)
         |> assign(:channel_unread, channel_unread)
         |> assign(:channel_highlight_message_id, channel_highlight_message_id)
         |> assign(:active_study_tool, nil)
         |> assign(:lesson_tab, :overview)
         |> assign(:preview?, preview?)
         |> assign(:requested_preview_lecture_id, params["lecture_id"])
         |> assign(:preview_progress, %{})
         |> assign(:preview_read_resource_ids, MapSet.new())
         |> assign(:study_guide_resource_id, nil)
         |> assign(:lq_submissions, %{})
         |> assign(:lecture_quiz, nil)
         |> assign(:lecture_quiz_answers, %{})
         |> assign(:lecture_quiz_result, nil)
         |> assign(:celebrating_certificate, nil)
         |> assign(:awaiting_certificate?, false)
         |> assign(:certificate_slow?, false)
         |> assign(:course_review, course_review)
         |> assign(:review_form_rating, nil)
         |> assign(:review_form_body, "")
         |> assign_lecture_quiz_gating()
         |> refresh_progress()
         |> load_lecture_quiz()}

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

  defp pdf_resource?(resource) do
    resource.kind == :document and
      (resource.content_type == "application/pdf" or
         String.downcase(Path.extname(resource.name || "")) == ".pdf")
  end

  @sections ~w(lessons module_quiz discussion)a

  # Reported by Hooks.CaptureGuard (throttled client-side to one event per
  # 5s per learner). Advisory only: the client is not trustworthy and these
  # attempts are trivially avoidable, so this drives review, never enforcement.
  @impl true
  def handle_event("capture-attempt", %{"kind" => kind}, socket)
      when kind in ~w(copy printscreen shortcut:p shortcut:s) do
    unless socket.assigns.preview? do
      Logger.warning(
        "capture attempt: kind=#{kind} user_id=#{socket.assigns.current_user.id} " <>
          "course=#{socket.assigns.course.slug} " <>
          "lecture_id=#{socket.assigns.current_lecture && socket.assigns.current_lecture.id}"
      )
    end

    {:noreply, socket}
  end

  def handle_event("capture-attempt", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select-section", %{"section" => section_str}, socket) do
    case safe_section(section_str) do
      {:ok, section} ->
        {:noreply,
         socket
         |> assign(:active_study_tool, nil)
         |> assign(:study_guide_resource_id, nil)
         |> enter_section(section)}

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select-study-tool", %{"tool" => tool}, socket)
      when tool in ["flashcards", "practice", "timed_quiz", "study_guide"] do
    # Picking a tool from the top nav is a lesson-wide ask, so it drops any
    # single-resource scope a "Study guide" button on a PDF had set.
    {:noreply,
     socket
     |> assign(:study_guide_resource_id, nil)
     |> assign(:active_study_tool, tool)}
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
  def handle_event("select-lesson-tab", %{"tab" => tab}, socket)
      when tab in ["overview", "practice", "quiz"] do
    {:noreply, assign(socket, :lesson_tab, String.to_existing_atom(tab))}
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
       |> assign(:lesson_tab, :overview)
       |> assign(:study_guide_resource_id, nil)
       |> assign(:lq_submissions, load_lq_submissions(socket, lecture))
       |> load_lecture_quiz()
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
  def handle_event(
        "select-lecture-quiz-option",
        %{"question-id" => q_id, "option-id" => opt_id},
        socket
      ) do
    answers =
      Map.put(socket.assigns.lecture_quiz_answers, to_string(q_id), to_string(opt_id))

    {:noreply, assign(socket, :lecture_quiz_answers, answers)}
  end

  @impl true
  def handle_event("submit-lecture-quiz", _params, socket) do
    case socket.assigns.lecture_quiz do
      %{quiz: quiz, questions: questions} ->
        answers = socket.assigns.lecture_quiz_answers

        if socket.assigns.preview? do
          {:noreply,
           assign(socket, :lecture_quiz_result, preview_quiz_result(quiz, questions, answers))}
        else
          submit_lecture_quiz(socket, quiz, answers)
        end

      nil ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("retake-lecture-quiz", _params, socket) do
    {:noreply,
     socket
     |> assign(:lecture_quiz_result, nil)
     |> assign(:lecture_quiz_answers, %{})}
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
          # Mirrors `Learning.record_progress/3`'s 95% auto-complete. Now that a
          # recording has no "Mark complete" button, this branch is the *only*
          # way a video lecture completes — without it, preview mode could never
          # reach a completed lecture, and the two modes would drift on exactly
          # the unlock rules this module exists to keep identical.
          status =
            if preview_watched_to_completion?(lecture, position),
              do: :completed,
              else: :in_progress

          {:noreply,
           socket
           |> put_preview_progress(lecture.id, status, position)
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

          # A reading-only lesson is completed by its PDFs, not by this event —
          # the UI offers no button for one. Rejected rather than trusted, since
          # the event itself is only as trustworthy as the client sending it.
          reading_only_lecture?(lecture) and
              unread_pdf_count(socket.assigns.read_resource_ids, lecture) > 0 ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Mark this lesson's PDFs as read to complete it."
             )}

          socket.assigns.preview? ->
            {:noreply,
             socket
             |> put_preview_progress(lecture.id, :completed, lecture.duration_seconds || 0)
             |> refresh_progress()
             |> focus_pending_quiz(lecture)
             |> put_flash(:info, "Lecture marked complete — preview only, nothing was saved.")}

          true ->
            persist_progress(socket, lecture, lecture.duration_seconds, true)
        end
    end
  end

  # One "mark complete" click for the whole lesson, from the end of its body.
  # A reading-only lesson completes by marking all its PDFs read (preserving the
  # existing per-resource events); any other non-video lesson completes directly.
  def handle_event("complete-lesson", %{"lecture_id" => lecture_id}, socket) do
    case current_lecture(socket, lecture_id) do
      nil ->
        {:noreply, socket}

      %{duration_seconds: seconds} when is_integer(seconds) ->
        # A video governs its own completion — nothing to click here.
        {:noreply, socket}

      lecture ->
        cond do
          socket.assigns.preview? ->
            socket =
              lecture
              |> lecture_pdfs()
              |> Enum.reduce(socket, fn resource, acc ->
                update(acc, :preview_read_resource_ids, &MapSet.put(&1, resource.id))
              end)
              |> put_preview_progress(lecture.id, :completed, 0)
              |> refresh_progress()
              |> focus_pending_quiz(lecture)

            {:noreply, put_flash(socket, :info, "Lesson marked complete — preview only.")}

          reading_only_lecture?(lecture) ->
            Enum.each(
              lecture_pdfs(lecture),
              &Learning.mark_resource_read(socket.assigns.current_user, &1)
            )

            {:noreply,
             socket
             |> refresh_progress()
             |> focus_pending_quiz(lecture)
             |> put_flash(:info, "Lesson marked as read.")}

          true ->
            persist_progress(socket, lecture, lecture.duration_seconds, true)
        end
    end
  end

  @impl true
  def handle_event("mark-resource-read", %{"resource_id" => resource_id}, socket) do
    case find_current_resource(socket, resource_id) do
      nil ->
        {:noreply, socket}

      resource ->
        if socket.assigns.preview? do
          {:noreply,
           socket
           |> update(:preview_read_resource_ids, &MapSet.put(&1, resource.id))
           |> refresh_progress()
           |> put_flash(:info, "Marked as read — preview only, nothing was saved.")}
        else
          case Learning.mark_resource_read(socket.assigns.current_user, resource) do
            {:ok, _events} ->
              {:noreply,
               socket
               |> refresh_progress()
               |> focus_pending_quiz(socket.assigns.current_lecture)
               |> put_flash(:info, resource_read_flash(socket, resource))}

            {:error, :forbidden} ->
              {:noreply, redirect_to_checkout(socket)}
          end
        end
    end
  end

  @impl true
  def handle_event("unmark-resource-read", %{"resource_id" => resource_id}, socket) do
    case find_current_resource(socket, resource_id) do
      nil ->
        {:noreply, socket}

      resource ->
        if socket.assigns.preview? do
          {:noreply,
           socket
           |> update(:preview_read_resource_ids, &MapSet.delete(&1, resource.id))
           |> refresh_progress()}
        else
          :ok = Learning.unmark_resource_read(socket.assigns.current_user, resource)
          {:noreply, refresh_progress(socket)}
        end
    end
  end

  # Opens the study-guide tool scoped to one document rather than the whole
  # lesson — "explain this handout" is a narrower ask than "explain this lesson",
  # and each resource keeps its own guides.
  @impl true
  def handle_event("resource-study-guide", %{"resource_id" => resource_id}, socket) do
    case find_current_resource(socket, resource_id) do
      nil ->
        {:noreply, socket}

      resource ->
        {:noreply,
         socket
         |> assign(:study_guide_resource_id, resource.id)
         |> assign(:active_study_tool, "study_guide")}
    end
  end

  def handle_event("dismiss-certificate-celebration", _params, socket) do
    {:noreply, assign(socket, :celebrating_certificate, nil)}
  end

  def handle_event("dismiss-awaiting-certificate", _params, socket) do
    {:noreply,
     socket
     |> assign(:awaiting_certificate?, false)
     |> assign(:certificate_slow?, false)}
  end

  @impl true
  def handle_event("select-rating", %{"rating" => rating_str}, socket) do
    case Integer.parse(rating_str) do
      {rating, ""} when rating in 1..5 ->
        {:noreply, assign(socket, :review_form_rating, rating)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("submit-course-review", params, socket) do
    rating =
      socket.assigns.review_form_rating ||
        case params["rating"] do
          r when is_binary(r) ->
            case Integer.parse(r) do
              {val, ""} when val in 1..5 -> val
              _ -> nil
            end

          r when is_integer(r) and r in 1..5 ->
            r

          _ ->
            nil
        end

    body = params["body"]

    if rating in 1..5 do
      case Reviews.upsert_course_review(
             socket.assigns.current_user,
             socket.assigns.course,
             %{"rating" => rating, "body" => body}
           ) do
        {:ok, review} ->
          socket =
            socket
            |> assign(:course_review, review)
            |> put_flash(:info, "Thank you for rating the course!")
            |> trigger_certificate_flow()

          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply,
           put_flash(socket, :error, "Could not save rating. Please select 1 to 5 stars.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select a star rating.")}
    end
  end

  defp trigger_certificate_flow(socket) do
    socket = refresh_certificates(socket)

    case List.first(socket.assigns.certificates) do
      nil ->
        Process.send_after(self(), :recheck_certificate, 4_000)
        Process.send_after(self(), :certificate_wait_elapsed, 5_000)
        assign(socket, :awaiting_certificate?, true)

      certificate ->
        certificate = %{certificate | course: socket.assigns.course}

        socket
        |> assign(:celebrating_certificate, certificate)
        |> assign(:awaiting_certificate?, false)
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

  defp enter_section(socket, :discussion = section) do
    if socket.assigns[:channel] && not socket.assigns.preview? do
      Channels.mark_read(socket.assigns.current_user, socket.assigns.channel)
    end

    socket
    |> assign(:active_section, section)
    |> assign(:channel_unread, 0)
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
        socket = socket |> refresh_progress() |> focus_pending_quiz(lecture)
        {:noreply, put_flash(socket, :info, lecture_completed_flash(socket, lecture))}

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

  # Mirrors `Learning`'s own 95% auto-complete ratio, for preview mode's
  # in-memory progress — see the `video-progress` handler for why preview needs
  # its own copy of the rule.
  @preview_completion_ratio 0.95

  defp preview_watched_to_completion?(%{duration_seconds: nil}, _position), do: false

  defp preview_watched_to_completion?(%{duration_seconds: duration}, position)
       when is_number(position),
       do: position >= duration * @preview_completion_ratio

  defp preview_watched_to_completion?(_lecture, _position), do: false

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
      when event in [:lecture_completed, :module_completed] do
    {:noreply, refresh_progress(socket)}
  end

  # When the course is fully completed, refresh progress.
  # If the learner hasn't rated the course yet, we let them rate inline on the page.
  # If already rated, we trigger the certificate flow directly.
  def handle_info({:course_completed, _subject}, socket) do
    socket = refresh_progress(socket)

    cond do
      socket.assigns.preview? ->
        {:noreply, socket}

      not is_nil(socket.assigns.celebrating_certificate) ->
        {:noreply, socket}

      is_nil(socket.assigns.course_review) ->
        {:noreply, socket}

      true ->
        {:noreply, trigger_certificate_flow(socket)}
    end
  end

  # Presence diffs on the channel topic are for the nested `ChannelLive`, not
  # the player itself.
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, socket}
  end

  # Channel activity: keep the Discussion tab's unread badge live while the
  # learner is elsewhere in the player. The nested `ChannelLive` handles its
  # own rendering when the tab is open.
  def handle_info({:message_created, message}, socket) do
    if not socket.assigns.preview? and socket.assigns.active_section != :discussion and
         message.user_id != socket.assigns.current_user.id do
      {:noreply, update(socket, :channel_unread, &(&1 + 1))}
    else
      {:noreply, socket}
    end
  end

  # Everything else on the channel topic (edits, deletes, reactions, typing
  # pings) is the nested `ChannelLive`'s concern — the player just ignores it.
  def handle_info({:message_deleted, _id}, socket), do: {:noreply, socket}
  def handle_info({:message_updated, _message}, socket), do: {:noreply, socket}
  def handle_info({:message_reacted, _id}, socket), do: {:noreply, socket}
  def handle_info({:typing, _payload}, socket), do: {:noreply, socket}

  # Only celebrate here if the ready certificate belongs to the course this
  # player is currently open on — PubSub is per-user, not per-course, so a
  # certificate finishing for some other course this learner is also
  # enrolled in shouldn't pop a modal over whatever they're doing here.
  def handle_info({:certificate_ready, %{course_id: course_id} = certificate}, socket) do
    socket = refresh_certificates(socket)

    if course_id == socket.assigns.course.id do
      certificate = %{certificate | course: socket.assigns.course}

      # If the learner just completed the course and hasn't rated it yet,
      # hold the celebration modal until they submit/skip the rating prompt on the page.
      if is_nil(socket.assigns.course_review) and
           socket.assigns.course_progress.complete? and
           not socket.assigns.awaiting_certificate? and
           not socket.assigns.preview? do
        {:noreply, socket}
      else
        {:noreply,
         socket
         |> assign(:celebrating_certificate, certificate)
         |> assign(:awaiting_certificate?, false)}
      end
    else
      {:noreply, socket}
    end
  end

  # Backup for a missed `:certificate_ready` (e.g. a LiveView reconnect while the
  # generation job was running): poll once the "preparing" modal is up.
  def handle_info(:recheck_certificate, socket) do
    socket = refresh_certificates(socket)

    cond do
      not socket.assigns.awaiting_certificate? or
          not is_nil(socket.assigns.celebrating_certificate) ->
        {:noreply, socket}

      certificate = List.first(socket.assigns.certificates) ->
        {:noreply,
         socket
         |> assign(
           :celebrating_certificate,
           %{certificate | course: socket.assigns.course}
         )
         |> assign(:awaiting_certificate?, false)}

      not socket.assigns.certificate_slow? ->
        Process.send_after(self(), :recheck_certificate, 4_000)
        {:noreply, socket}

      true ->
        {:noreply, socket}
    end
  end

  # The certificate is taking longer than a learner should wait on a modal —
  # swap to copy that sends them on their way.
  def handle_info(:certificate_wait_elapsed, socket) do
    {:noreply, assign(socket, :certificate_slow?, socket.assigns.awaiting_certificate?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-surface text-body">
      <div
        :if={@awaiting_certificate? && is_nil(@celebrating_certificate)}
        id="certificate-preparing"
        phx-window-keydown="dismiss-awaiting-certificate"
        phx-key="Escape"
        class="fixed inset-0 z-50 flex items-center justify-center bg-ink/60 px-4 backdrop-blur-sm"
      >
        <div class="relative w-full max-w-md rounded-3xl bg-white p-8 text-center shadow-2xl">
          <button
            type="button"
            phx-click="dismiss-awaiting-certificate"
            class="absolute right-4 top-4 text-muted transition hover:text-ink"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="h-5 w-5" />
          </button>

          <div class="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-mint">
            <.icon name="hero-sparkles" class="h-8 w-8 text-primary" />
          </div>
          <h2 class="mt-4 text-2xl font-semibold text-ink">Thanks — you're all done!</h2>
          <p class="mt-1 text-body">
            You've completed <span class="font-semibold text-ink">{@course.title}</span>.
          </p>
          <p :if={!@certificate_slow?} class="mt-4 inline-flex items-center gap-2 text-sm text-muted">
            <.icon name="hero-arrow-path" class="h-4 w-4 animate-spin" /> Preparing your certificate…
          </p>
          <p :if={@certificate_slow?} class="mt-4 text-sm text-body">
            Your certificate is taking a little longer than usual. It'll be waiting under
            <span class="font-semibold text-ink">Certificates</span>
            shortly — no need to stay here.
          </p>

          <div class="mt-6 flex flex-col gap-3 sm:flex-row sm:justify-center">
            <.link
              navigate={~p"/certificates"}
              class="inline-flex items-center justify-center gap-2 rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-ink"
            >
              <.icon name="hero-trophy" class="h-4 w-4" /> Go to my certificates
            </.link>
            <button
              type="button"
              phx-click="dismiss-awaiting-certificate"
              class="inline-flex items-center justify-center gap-2 rounded-full border border-black/10 px-5 py-2.5 text-sm font-semibold text-ink transition hover:border-primary hover:text-primary"
            >
              Keep learning
            </button>
          </div>
        </div>
      </div>

      <div
        :if={@celebrating_certificate}
        id="certificate-celebration"
        phx-hook="Confetti"
        phx-window-keydown="dismiss-certificate-celebration"
        phx-key="Escape"
        class="fixed inset-0 z-50 flex items-center justify-center bg-ink/60 px-4 backdrop-blur-sm"
      >
        <div class="relative w-full max-w-2xl rounded-3xl bg-white p-8 text-center shadow-2xl">
          <button
            type="button"
            phx-click="dismiss-certificate-celebration"
            class="absolute right-4 top-4 text-muted transition hover:text-ink"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="h-5 w-5" />
          </button>

          <div class="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-mint">
            <.icon name="hero-trophy" class="h-8 w-8 text-primary" />
          </div>

          <h2 class="mt-4 text-2xl font-bold text-ink">Congratulations!</h2>
          <p class="mt-1 text-body">
            You've completed <span class="font-semibold text-ink">{@celebrating_certificate.course.title}</span>.
            Your certificate is ready.
          </p>

          <img
            src={~p"/certificates/#{@celebrating_certificate.id}/preview"}
            alt={"Certificate — #{@celebrating_certificate.course.title}"}
            loading="lazy"
            onerror="this.remove()"
            class="mx-auto mt-6 w-full rounded-xl border border-black/10 shadow-md"
          />

          <div class="mt-8 flex flex-col gap-3 sm:flex-row sm:justify-center">
            <.link
              href={~p"/certificates/#{@celebrating_certificate.id}/download"}
              class="inline-flex items-center justify-center gap-2 rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-ink"
            >
              <.icon name="hero-arrow-down-tray" class="h-4 w-4" /> Download certificate
            </.link>
            <.link
              href={Certificates.linkedin_add_to_profile_url(@celebrating_certificate)}
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center justify-center gap-2 rounded-full border border-black/10 px-5 py-2.5 text-sm font-semibold text-ink transition hover:border-primary hover:text-primary"
            >
              <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" /> Add to LinkedIn
            </.link>
          </div>
        </div>
      </div>

      <header class="sticky top-0 z-40 border-b border-black/10 bg-white">
        <div class="flex items-center justify-between gap-4 px-4 py-2.5 sm:px-6">
          <div class="flex min-w-0 items-center gap-3">
            <img src={~p"/images/logo.png"} alt="Wasomi" class="h-6 w-auto shrink-0" />
            <span class="hidden h-5 w-px bg-black/10 sm:block"></span>
            <p class="min-w-0 truncate text-sm font-medium text-dark">{@course.title}</p>
            <span
              id="course-progress-percent"
              class="hidden shrink-0 text-xs font-semibold text-primary sm:inline"
            >
              {@course_progress.percent}% complete
            </span>
          </div>
          <.link
            navigate={if @preview?, do: ~p"/admin/courses/#{@course.slug}", else: ~p"/courses-taken"}
            class="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-black/15 px-3 py-1.5 text-sm font-semibold text-dark transition hover:border-dark hover:bg-dark hover:text-white"
            aria-label="Exit course"
          >
            <.icon name="hero-x-mark" class="h-5 w-5" />
            <span class="hidden sm:inline">Exit</span>
          </.link>
        </div>
        <div class="h-1 w-full bg-surface">
          <div
            id="course-progress-bar"
            class="h-full bg-primary transition-all duration-500"
            style={"width: #{@course_progress.percent}%"}
          >
          </div>
        </div>
      </header>

      <div class="course-workspace pb-12">
        <div id="course-player" {capture_guard_attrs(@current_user)}>
          <div class="mx-auto max-w-[1720px] px-5 py-6 sm:px-8 lg:px-12">
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

            <div class="mt-2 lg:grid lg:grid-cols-[320px_minmax(0,1fr)] lg:items-start lg:gap-5">
              <aside class="mb-4 flex max-h-[calc(100vh-2rem)] flex-col overflow-hidden rounded-2xl bg-white lg:mb-0 lg:sticky lg:top-4">
                <% course_resources = course_resources(@course) %>
                <div class="flex border-b border-black/10">
                  <button
                    id="outline-tab"
                    type="button"
                    phx-click={switch_outline_tab(:outline)}
                    class="flex-1 border-b-2 border-primary px-4 py-3 text-sm font-semibold text-dark transition"
                  >
                    Outline
                  </button>
                  <button
                    id="resources-tab"
                    type="button"
                    phx-click={switch_outline_tab(:resources)}
                    class="flex flex-1 items-center justify-center gap-1.5 border-b-2 border-transparent px-4 py-3 text-sm font-semibold text-muted transition"
                  >
                    Resources
                    <span
                      :if={course_resources != []}
                      class="rounded-full bg-surface px-1.5 text-[11px] font-bold text-muted"
                    >
                      {length(course_resources)}
                    </span>
                  </button>
                </div>

                <div id="resources-panel" class="hidden overflow-y-auto p-3">
                  <p :if={course_resources == []} class="p-4 text-sm text-muted">
                    No downloadable resources for this course yet.
                  </p>
                  <ul class="space-y-1">
                    <li :for={resource <- course_resources}>
                      <.link
                        href={resource_download_path(resource.id, @preview?)}
                        target={if resource.kind == :link, do: "_blank"}
                        class="flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm text-body transition hover:bg-surface"
                      >
                        <span class="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-mint text-primary">
                          <.icon name={resource_icon(resource.kind)} class="h-4 w-4" />
                        </span>
                        <span class="min-w-0 flex-1 truncate">{resource.name}</span>
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

                <%!-- Separators are drawn with divide-y rather than a border-b per row: the
                last row in the list then has no trailing line to collide with the card's
                rounded bottom corners. --%>
                <div id="outline-panel" class="divide-y divide-black/10 overflow-y-auto">
                  <section :for={module <- @course.modules} class="divide-y divide-black/10">
                    <button
                      type="button"
                      aria-expanded="true"
                      aria-controls={"module-#{module.id}-lectures"}
                      phx-click={
                        JS.toggle(to: "#module-#{module.id}-lectures")
                        |> JS.toggle_attribute({"aria-expanded", "true", "false"})
                        |> JS.toggle_class("-rotate-90", to: "#module-#{module.id}-chevron")
                      }
                      class="group/module flex w-full items-center justify-between gap-3 bg-[#f5f5f5] px-5 py-3.5 text-left transition hover:bg-[#efefef]"
                    >
                      <span class="min-w-0">
                        <span class="text-[11px] font-bold uppercase tracking-wider text-primary">
                          Module {module.position}
                        </span>
                        <span class="mt-0.5 block truncate text-sm font-semibold text-dark">
                          {module.title}
                        </span>
                      </span>
                      <span
                        id={"module-#{module.id}-chevron"}
                        class="grid h-8 w-8 shrink-0 place-items-center rounded-full border border-black/10 bg-white text-dark shadow-sm transition group-hover/module:border-primary/20 group-hover/module:bg-mint group-hover/module:text-primary"
                      >
                        <.icon name="hero-chevron-down" class="h-4 w-4" />
                      </span>
                    </button>
                    <div id={"module-#{module.id}-lectures"} class="divide-y divide-black/10">
                      <%!-- The tooltip is the answer to "why can't I move on?" — it names the
                      one outstanding thing, whether that's watching, reading, or sitting the
                      lesson quiz. `title` carries it for screen readers and for the disabled
                      (locked) rows, where a CSS-only hover panel is unreliable. --%>
                      <div :for={lecture <- module.lectures} class="group/lesson relative">
                        <button
                          type="button"
                          phx-click="select-lecture"
                          phx-value-id={lecture.id}
                          disabled={!lecture_unlocked?(@unlocked_lecture_ids, lecture.id)}
                          data-lecture-id={lecture.id}
                          title={lecture_todo_hint(assigns, lecture)}
                          data-locked={
                            if lecture_unlocked?(@unlocked_lecture_ids, lecture.id),
                              do: "false",
                              else: "true"
                          }
                          class={[
                            "flex w-full items-center gap-3 px-5 py-3 text-left text-sm transition",
                            @current_lecture && @current_lecture.id == lecture.id &&
                              "border-l-4 border-l-primary bg-[#f5f5f5] pl-4 font-semibold text-body",
                            (!@current_lecture || @current_lecture.id != lecture.id) &&
                              lecture_unlocked?(@unlocked_lecture_ids, lecture.id) &&
                              "text-body hover:bg-[#f5f5f5]",
                            !lecture_unlocked?(@unlocked_lecture_ids, lecture.id) &&
                              "cursor-not-allowed text-muted"
                          ]}
                        >
                          <span class={[
                            "grid h-6 w-6 shrink-0 place-items-center rounded-full text-xs font-semibold",
                            progress_status(@progress, lecture.id) == :completed &&
                              lecture_unlocked?(@unlocked_lecture_ids, lecture.id) &&
                              "bg-primary text-white",
                            progress_status(@progress, lecture.id) != :completed &&
                              lecture_unlocked?(@unlocked_lecture_ids, lecture.id) &&
                              "bg-mint text-primary",
                            !lecture_unlocked?(@unlocked_lecture_ids, lecture.id) && "text-muted/60"
                          ]}>
                            <%!-- One glyph only: a locked lecture reads as locked even if an
                            earlier pass completed it, so the padlock wins over the tick. --%>
                            <.icon
                              :if={!lecture_unlocked?(@unlocked_lecture_ids, lecture.id)}
                              name="hero-lock-closed"
                              class="h-3.5 w-3.5"
                            />
                            <.icon
                              :if={
                                lecture_unlocked?(@unlocked_lecture_ids, lecture.id) &&
                                  progress_status(@progress, lecture.id) == :completed
                              }
                              name="hero-check"
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
                            <% lesson_minutes = lecture_estimated_minutes(lecture) %>
                            <span
                              :if={lesson_minutes || resource_type_badges(assigns, lecture) != []}
                              class="mt-1 flex flex-wrap items-center gap-x-2.5 gap-y-1 text-xs text-muted"
                            >
                              <span :if={lesson_minutes} class="inline-flex items-center gap-1">
                                <.icon name="hero-clock" class="h-3.5 w-3.5" />
                                {lesson_minutes} min
                              </span>
                              <span
                                :for={badge <- resource_type_badges(assigns, lecture)}
                                class="inline-flex items-center gap-1"
                              >
                                <.icon name={badge.icon} class="h-3.5 w-3.5" />
                                {badge.label}
                              </span>
                            </span>
                            <%!-- The one status worth a line: it's the answer to "why is the
                            next lesson locked?" --%>
                            <span
                              :if={lecture_quiz_passed?(assigns, lecture)}
                              class="mt-1 inline-flex items-center gap-1 text-xs font-medium text-primary"
                            >
                              <.icon name="hero-clipboard-document-check" class="h-3.5 w-3.5" />
                              Quiz passed
                            </span>
                            <span
                              :if={lecture_quiz_pending?(assigns, lecture)}
                              class="mt-1 inline-flex items-center gap-1 text-xs text-muted"
                            >
                              <.icon name="hero-clipboard-document-check" class="h-3.5 w-3.5" />
                              Quiz to pass
                            </span>
                          </span>
                        </button>
                        <% hint = lecture_todo_hint(assigns, lecture) %>
                        <span
                          :if={hint}
                          role="tooltip"
                          class="pointer-events-none absolute bottom-full left-6 right-6 z-20 mb-1 hidden rounded-xl bg-ink px-3 py-2 text-xs font-medium leading-snug text-white shadow-lg group-hover/lesson:block"
                        >
                          {hint}
                        </span>
                      </div>

                      <% quiz_unlocked? = module_quiz_unlocked?(module, @progress, @preview?) %>
                      <button
                        :if={module_quiz = Map.get(@quizzes_by_module, module.id)}
                        type="button"
                        phx-click="select-quiz"
                        phx-value-module_id={module.id}
                        disabled={!quiz_unlocked?}
                        data-locked={if quiz_unlocked?, do: "false", else: "true"}
                        class={[
                          "flex w-full items-center gap-3 px-5 py-3 text-left text-sm transition",
                          @current_quiz && @current_quiz.quiz.id == module_quiz.id &&
                            "border-l-4 border-l-primary bg-[#f5f5f5] pl-4 font-semibold text-primary",
                          (!@current_quiz || @current_quiz.quiz.id != module_quiz.id) &&
                            quiz_unlocked? &&
                            "text-body hover:bg-[#f5f5f5]",
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
                          <span class="block font-medium truncate">
                            Module {module.position} Quiz
                          </span>
                        </span>
                      </button>
                    </div>
                  </section>
                </div>
              </aside>
              <div class="min-w-0 space-y-6">
                <nav class="flex items-center gap-1 overflow-x-auto rounded-2xl border border-black/10 bg-white p-1.5 lg:overflow-visible">
                  <button
                    :for={{section, label, icon, description} <- section_nav_items()}
                    type="button"
                    phx-click="select-section"
                    phx-value-section={section}
                    class={[
                      "group/top-tooltip relative flex flex-1 basis-0 min-w-0 items-center justify-center gap-2 whitespace-nowrap rounded-xl px-3 py-2 text-sm font-semibold transition",
                      is_nil(@active_study_tool) && @active_section == section &&
                        "bg-dark text-white",
                      (!is_nil(@active_study_tool) || @active_section != section) &&
                        "text-body hover:bg-surface"
                    ]}
                  >
                    <.icon name={icon} class="h-4 w-4 shrink-0" />
                    {label}<span :if={section == :lessons} class="sr-only">Lessons</span>
                    <.course_nav_tooltip label={description} />
                  </button>
                  <button
                    type="button"
                    phx-click="select-section"
                    phx-value-section="module_quiz"
                    class="sr-only"
                  >
                    Module quiz
                  </button>
                  <button
                    type="button"
                    phx-click="select-section"
                    phx-value-section="discussion"
                    class={[
                      "group/top-tooltip relative flex flex-1 basis-0 min-w-0 items-center justify-center gap-2 whitespace-nowrap rounded-xl px-3 py-2 text-sm font-semibold transition",
                      is_nil(@active_study_tool) && @active_section == :discussion &&
                        "bg-dark text-white",
                      (!is_nil(@active_study_tool) || @active_section != :discussion) &&
                        "text-body hover:bg-surface"
                    ]}
                  >
                    <.icon name="hero-chat-bubble-left-right" class="h-4 w-4 shrink-0" /> Discussion
                    <span
                      :if={@channel_unread > 0}
                      class="grid h-4 min-w-4 place-items-center rounded-full bg-primary px-1 text-[10px] font-bold leading-none text-white"
                    >
                      {min(@channel_unread, 99)}
                    </span>
                    <.course_nav_tooltip label="Talk with your cohort and the course team." />
                  </button>
                  <button
                    :for={{mode, label, icon, description} <- study_hub_nav_items()}
                    type="button"
                    phx-click="select-study-tool"
                    phx-value-tool={mode}
                    class={[
                      "group/top-tooltip relative flex flex-1 basis-0 min-w-0 items-center justify-center gap-2 whitespace-nowrap rounded-xl px-3 py-2 text-sm font-semibold transition",
                      @active_study_tool == mode && "bg-dark text-white",
                      @active_study_tool != mode && "text-body hover:bg-surface"
                    ]}
                  >
                    <.icon name={icon} class="h-4 w-4 shrink-0" />
                    {label}
                    <.course_nav_tooltip label={description} />
                  </button>
                </nav>

                <section :if={@active_study_tool}>
                  {live_render(@socket, WasomiWeb.EmbeddedStudyHubLive,
                    id:
                      "embedded-study-tool-#{@active_study_tool}-#{@study_guide_resource_id || "lesson"}",
                    session:
                      embedded_study_hub_session(
                        @current_user,
                        @course,
                        current_module(assigns),
                        @active_study_tool,
                        @study_guide_resource_id
                      )
                  )}
                </section>

                <section
                  :if={@active_section == :discussion && is_nil(@active_study_tool)}
                  class="overflow-hidden rounded-3xl bg-white"
                >
                  {live_render(@socket, WasomiWeb.ChannelLive,
                    id: "course-channel",
                    sticky: true,
                    session: %{
                      "current_user_id" => @current_user.id,
                      "course_slug" => @course.slug,
                      "highlight_message_id" => @channel_highlight_message_id
                    }
                  )}
                </section>

                <div :if={@active_section == :lessons && is_nil(@active_study_tool)}>
                  <section class="overflow-hidden rounded-3xl bg-white">
                    <%= if @current_quiz do %>
                      <.quiz_taking_panel
                        current_quiz={@current_quiz}
                        quiz_result={@quiz_result}
                        quiz_answers={@quiz_answers}
                        current_question_index={@current_question_index}
                      />
                    <% else %>
                      <%= if @current_lecture do %>
                        <% module = current_module(assigns) %>
                        <% has_pdf_resources? =
                          Enum.any?(@current_lecture.resources, &pdf_resource?/1) %>
                        <header
                          :if={!has_pdf_resources?}
                          class="flex flex-wrap items-center gap-x-2 gap-y-1 border-b border-black/10 px-7 py-4 text-sm sm:px-10"
                        >
                          <h2 class="font-semibold text-dark">{@current_lecture.title}</h2>
                          <span class="text-muted">
                            · Lesson {lecture_number(@course, @current_lecture)} of {@course_progress.total}
                          </span>
                          <span :if={module} class="text-muted">· {module.title}</span>
                        </header>

                        <div :if={@current_lecture.duration_seconds} class="bg-dark p-4 sm:p-6">
                          <div
                            id={"protected-player-#{@current_lecture.id}"}
                            phx-hook="ProtectedVideo"
                            phx-update="ignore"
                            data-playback-url={playback_url_path(@current_lecture.id, @preview?)}
                            data-video-title={@current_lecture.title}
                            data-viewer-id={@current_user.id}
                            data-lecture-id={@current_lecture.id}
                            data-preview={to_string(@preview?)}
                            data-start-position={progress_position(@progress, @current_lecture.id)}
                            data-seek-unlocked={
                              to_string(progress_status(@progress, @current_lecture.id) == :completed)
                            }
                            data-watermark={watermark_text(@current_user)}
                            class="relative mx-auto aspect-video w-full overflow-hidden rounded-2xl bg-black shadow-2xl ring-1 ring-white/15"
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
                              {watermark_text(@current_user)}
                            </div>
                          </div>
                        </div>
                        <% completed? = progress_status(@progress, @current_lecture.id) == :completed %>
                        <% has_video? = not is_nil(@current_lecture.duration_seconds) %>
                        <% reading_only? = reading_only_lecture?(@current_lecture) %>
                        <% tabs = lesson_tabs(assigns) %>
                        <% active_tab =
                          if Enum.any?(tabs, &(&1.id == @lesson_tab)),
                            do: @lesson_tab,
                            else: :overview %>
                        <% show_course_rating? =
                          final_lecture?(@course, @current_lecture) && !@preview? &&
                            (completed? || @course_progress.complete?) %>

                        <%!-- One tab ("Lesson") means nothing to switch between — hide the strip. --%>
                        <div
                          :if={length(tabs) > 1}
                          id="lesson-tabs"
                          role="tablist"
                          aria-label="Lesson material"
                          class="flex gap-1 overflow-x-auto border-b border-black/5 px-7 sm:px-10"
                        >
                          <button
                            :for={tab <- tabs}
                            id={"lesson-tab-#{tab.id}"}
                            type="button"
                            role="tab"
                            aria-selected={to_string(active_tab == tab.id)}
                            phx-click={
                              JS.push("select-lesson-tab", value: %{tab: to_string(tab.id)})
                              |> JS.dispatch("wasomi:scroll-into-view", to: "#lesson-tabs")
                            }
                            class={[
                              "-mb-px inline-flex shrink-0 items-center gap-2 border-b-2 px-3 py-4 text-sm font-semibold transition",
                              active_tab == tab.id && "border-primary text-primary",
                              active_tab != tab.id &&
                                "border-transparent text-body hover:border-black/20 hover:text-ink"
                            ]}
                          >
                            <.icon name={tab.icon} class="h-4 w-4 shrink-0" />
                            <span>{tab.label}</span>
                            <span
                              :if={tab.count && tab.flag != :required}
                              class="rounded-full bg-black/5 px-1.5 py-0.5 text-[11px] font-bold"
                            >
                              {tab.count}
                            </span>
                            <span
                              :if={tab.flag == :required}
                              class="inline-flex items-center gap-1.5 rounded-full bg-primary/10 px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide text-primary"
                            >
                              <span class="h-1.5 w-1.5 animate-pulse rounded-full bg-primary"></span>
                              Required
                            </span>
                            <.icon
                              :if={tab.flag == :passed}
                              name="hero-check-circle"
                              class="h-4 w-4 shrink-0 text-primary"
                            />
                          </button>
                        </div>

                        <div
                          id="lesson-overview"
                          role="tabpanel"
                          aria-labelledby="lesson-tab-overview"
                          class={[
                            "space-y-8 bg-white p-7 sm:p-10",
                            active_tab != :overview && "hidden"
                          ]}
                        >
                          <%!-- Skip the description when a PDF reader follows — the section
                          header already names the lesson, and the reader is the content. --%>
                          <p
                            :if={
                              !show_course_rating? &&
                                @current_lecture.description not in [nil, ""] &&
                                !Enum.any?(@current_lecture.resources, &pdf_resource?/1)
                            }
                            class="max-w-2xl leading-relaxed text-body"
                          >
                            {@current_lecture.description}
                          </p>
                          <p
                            :if={
                              !show_course_rating? &&
                                @current_lecture.description in [nil, ""] &&
                                !Enum.any?(@current_lecture.resources, &pdf_resource?/1)
                            }
                            class="text-sm text-muted"
                          >
                            This lesson is the recording above — it has no written notes.
                          </p>

                          <%!-- Final course feedback replaces the lesson PDF once the final
                          lecture is complete, so the learner has one clear next action before
                          the certificate celebration. --%>
                          <div
                            :if={show_course_rating?}
                            id="course-rating-section"
                            class="grid min-h-[360px] place-items-center rounded-2xl border border-black/10 bg-white px-5 py-8 sm:px-8"
                          >
                            <%= if is_nil(@course_review) do %>
                              <div class="w-full max-w-2xl rounded-2xl bg-soft/70 p-5 sm:p-7">
                                <div>
                                  <span class="inline-flex items-center gap-1.5 rounded-full bg-mint px-3 py-1 text-xs font-semibold uppercase tracking-wider text-primary">
                                    <.icon name="hero-star" class="h-4 w-4" /> Course feedback
                                  </span>
                                  <h3 class="mt-3 text-xl font-semibold text-ink">
                                    Rate this course
                                  </h3>
                                  <p class="mt-2 text-sm text-body">
                                    How was your experience with <span class="font-semibold">{@course.title}</span>? Your feedback helps us improve.
                                  </p>
                                </div>

                                <form
                                  id="course-review-form"
                                  phx-submit="submit-course-review"
                                  class="mt-6 space-y-5"
                                >
                                  <div class="rounded-2xl border border-black/5 bg-white p-4">
                                    <label class="block text-xs font-semibold uppercase tracking-wider text-muted">
                                      Rating <span class="text-red-500">*</span>
                                    </label>
                                    <div class="mt-3 flex flex-wrap items-center gap-1.5">
                                      <button
                                        :for={star <- 1..5}
                                        type="button"
                                        id={"rate-star-#{star}"}
                                        phx-click="select-rating"
                                        phx-value-rating={star}
                                        class="group p-1 transition active:scale-95"
                                        aria-label={"Rate #{star} out of 5 stars"}
                                      >
                                        <.icon
                                          name="hero-star-solid"
                                          class={"h-7 w-7 transition #{if((@review_form_rating || 0) >= star, do: "text-amber-400", else: "text-black/15 hover:text-amber-300")}"}
                                        />
                                      </button>
                                      <span
                                        :if={@review_form_rating}
                                        class="ml-2 text-sm font-semibold text-ink"
                                      >
                                        {case @review_form_rating do
                                          1 -> "1 - Poor"
                                          2 -> "2 - Fair"
                                          3 -> "3 - Good"
                                          4 -> "4 - Very Good"
                                          5 -> "5 - Excellent!"
                                          _ -> ""
                                        end}
                                      </span>
                                    </div>
                                  </div>

                                  <div class="rounded-2xl border border-black/5 bg-white p-4">
                                    <label
                                      for="review-body"
                                      class="block text-xs font-semibold uppercase tracking-wider text-muted"
                                    >
                                      Written comment
                                      <span class="font-normal lowercase text-muted/80">
                                        (optional)
                                      </span>
                                    </label>
                                    <textarea
                                      id="review-body"
                                      name="body"
                                      rows="3"
                                      placeholder="Share what you enjoyed or suggestions for improvement..."
                                      class="mt-3 block w-full rounded-xl border border-black/10 bg-white px-4 py-3 text-sm text-ink placeholder-muted focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
                                    >{@review_form_body}</textarea>
                                  </div>

                                  <div class="flex justify-end">
                                    <button
                                      type="submit"
                                      id="submit-course-rating"
                                      disabled={is_nil(@review_form_rating)}
                                      class="rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-white transition hover:bg-ink disabled:cursor-not-allowed disabled:opacity-40"
                                    >
                                      Submit & view certificate
                                    </button>
                                  </div>
                                </form>
                              </div>
                            <% else %>
                              <div class="w-full max-w-xl rounded-2xl bg-soft/70 p-6 text-center sm:p-8">
                                <span class="inline-flex items-center gap-1.5 rounded-full bg-mint px-3 py-1 text-xs font-semibold uppercase tracking-wider text-primary">
                                  <.icon name="hero-check-circle" class="h-4 w-4" />
                                  Feedback submitted
                                </span>
                                <h3 class="mt-3 text-xl font-semibold text-ink">
                                  Thanks for the feedback
                                </h3>
                                <div class="mt-4 flex flex-wrap items-center justify-center gap-1.5">
                                  <.icon
                                    :for={n <- 1..5}
                                    name="hero-star-solid"
                                    class={"h-6 w-6 #{if(@course_review.rating >= n, do: "text-amber-400", else: "text-black/15")}"}
                                  />
                                  <span class="ml-2 text-sm font-semibold text-ink">
                                    {@course_review.rating}/5 stars
                                  </span>
                                </div>
                                <p
                                  :if={@course_review.body}
                                  class="mx-auto mt-3 max-w-md text-sm italic text-body"
                                >
                                  "{@course_review.body}"
                                </p>
                                <p class="mt-3 text-sm text-muted">
                                  Thank you for rating this course!
                                </p>
                                <.link
                                  :if={@certificates != []}
                                  href={~p"/certificates/#{List.first(@certificates).id}/download"}
                                  class="mt-4 inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-ink"
                                >
                                  <.icon name="hero-arrow-down-tray" class="h-4 w-4" />
                                  Download certificate
                                </.link>
                              </div>
                            <% end %>
                          </div>

                          <div
                            :if={
                              !show_course_rating? &&
                                Enum.any?(@current_lecture.resources, &pdf_resource?/1)
                            }
                            id="lesson-pdfs"
                            class="space-y-5"
                          >
                            <div
                              :for={
                                resource <-
                                  Enum.filter(@current_lecture.resources, &pdf_resource?/1)
                              }
                              id={"pdf-resource-#{resource.id}"}
                              class="overflow-hidden rounded-2xl border border-black/10 bg-white"
                            >
                              <div
                                id={"pdf-deck-#{resource.id}"}
                                phx-hook="PdfDeck"
                                phx-update="ignore"
                                data-src={resource_download_path(resource.id, @preview?)}
                                data-viewer-src={~p"/assets/pdf.min.mjs"}
                                data-worker-src={~p"/assets/pdf.worker.min.mjs"}
                                data-title={resource.name}
                                class="bg-white"
                              >
                              </div>
                            </div>
                          </div>
                        </div>

                        <div
                          :if={@current_lecture.questions != []}
                          id="lecture-faq"
                          role="tabpanel"
                          aria-labelledby="lesson-tab-practice"
                          class={["bg-white p-8 lg:p-10", active_tab != :practice && "hidden"]}
                        >
                          <h3 class="text-xs font-medium uppercase tracking-widest text-muted">
                            Practice questions
                          </h3>
                          <p class="mt-1 text-xs text-muted">
                            Type your answer and submit — you'll get instant feedback. These are not
                            graded.
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

                        <div
                          :if={@lecture_quiz}
                          id="lesson-quiz"
                          role="tabpanel"
                          aria-labelledby="lesson-tab-quiz"
                          class={["bg-white p-8 lg:p-10", active_tab != :quiz && "hidden"]}
                        >
                          <% total = length(@lecture_quiz.questions) %>
                          <div class="flex flex-wrap items-start justify-between gap-4">
                            <div>
                              <h3 class="text-xs font-medium uppercase tracking-widest text-muted">
                                Lesson quiz
                              </h3>
                              <p class="mt-1 text-sm text-body">
                                {total} questions · score
                                <span class="font-semibold text-primary">
                                  {@lecture_quiz.quiz.passing_score_percent}%
                                </span>
                                to unlock the next lesson.
                              </p>
                            </div>
                            <span
                              :if={@lecture_quiz_result && @lecture_quiz_result.passed}
                              class="inline-flex items-center gap-2 rounded-full bg-mint px-3 py-1 text-xs font-semibold text-primary"
                            >
                              <.icon name="hero-check-circle" class="h-4 w-4" /> Passed
                            </span>
                          </div>

                          <div
                            :if={@lecture_quiz_result}
                            class={[
                              "mt-5 rounded-2xl p-5 text-sm text-ink",
                              if(@lecture_quiz_result.passed, do: "bg-mint", else: "bg-red-50")
                            ]}
                          >
                            <p class="font-semibold">
                              You scored {@lecture_quiz_result.score_percent}% — {if(
                                @lecture_quiz_result.passed,
                                do: "passed.",
                                else: "not passed yet."
                              )}
                            </p>
                            <p
                              :if={Map.get(@lecture_quiz_result, :preview?, false)}
                              class="mt-1 text-xs text-muted"
                            >
                              Admin preview result — scored in memory and not saved.
                            </p>
                            <p :if={!@lecture_quiz_result.passed} class="mt-1 text-body">
                              Review the lesson, then try again — the next lesson stays locked
                              until you pass.
                            </p>
                            <button
                              type="button"
                              phx-click="retake-lecture-quiz"
                              class="mt-4 rounded-full border border-black/10 bg-white px-5 py-2.5 text-sm font-semibold text-ink transition hover:bg-ink hover:text-white"
                            >
                              Retake quiz
                            </button>
                          </div>

                          <form
                            :if={is_nil(@lecture_quiz_result)}
                            phx-submit="submit-lecture-quiz"
                            class="mt-5 space-y-4"
                          >
                            <div
                              :for={{question, index} <- Enum.with_index(@lecture_quiz.questions, 1)}
                              class="rounded-2xl border border-black/5 p-5"
                            >
                              <p class="text-xs font-semibold uppercase tracking-wider text-primary">
                                Question {index} of {total}
                              </p>
                              <p class="mt-2 text-sm font-medium text-ink">{question.prompt}</p>
                              <div class="mt-3 space-y-2.5">
                                <label
                                  :for={option <- question.question_options}
                                  class={[
                                    "flex cursor-pointer items-center gap-3 rounded-xl border p-3.5 transition",
                                    if(
                                      to_string(
                                        Map.get(@lecture_quiz_answers, to_string(question.id))
                                      ) ==
                                        to_string(option.id),
                                      do: "border-primary bg-mint font-medium text-ink",
                                      else:
                                        "border-black/10 text-body hover:border-primary/40 hover:bg-mint/40"
                                    )
                                  ]}
                                >
                                  <input
                                    type="radio"
                                    name={"lecture_quiz_question_#{question.id}"}
                                    value={option.id}
                                    checked={
                                      to_string(
                                        Map.get(@lecture_quiz_answers, to_string(question.id))
                                      ) ==
                                        to_string(option.id)
                                    }
                                    phx-click="select-lecture-quiz-option"
                                    phx-value-question-id={question.id}
                                    phx-value-option-id={option.id}
                                    class="h-4 w-4 border-black/20 bg-white text-primary focus:ring-primary"
                                  />
                                  <span class="text-sm">{option.label}</span>
                                </label>
                              </div>
                            </div>

                            <div class="flex flex-wrap items-center justify-between gap-3 border-t border-black/5 pt-5">
                              <span class="text-xs text-muted">
                                Answered {map_size(@lecture_quiz_answers)} of {total} questions
                              </span>
                              <button
                                type="submit"
                                disabled={map_size(@lecture_quiz_answers) < total}
                                class="rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-white transition hover:bg-ink disabled:cursor-not-allowed disabled:opacity-40"
                              >
                                Submit quiz
                              </button>
                            </div>
                          </form>
                        </div>

                        <%!-- One completion control for the whole lesson, at the end of its
                        content. A video self-completes once watched, so it shows a readout
                        instead of a button. --%>
                        <div class="flex flex-wrap items-center justify-end gap-3 px-7 py-5 sm:px-10">
                          <p
                            :if={completed?}
                            class="inline-flex items-center gap-2 text-sm font-semibold text-primary"
                          >
                            <.icon name="hero-check-circle" class="h-5 w-5" /> Lesson complete
                          </p>
                          <button
                            :if={!completed? && !has_video?}
                            id="mark-lesson-complete"
                            type="button"
                            phx-click="complete-lesson"
                            phx-value-lecture_id={@current_lecture.id}
                            class="rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-white transition hover:bg-ink"
                          >
                            {if reading_only?,
                              do: "I've read this — mark complete",
                              else: "Mark lesson complete"}
                          </button>
                          <p
                            :if={!completed? && has_video?}
                            id="lecture-watch-progress"
                            class="inline-flex items-center gap-2 text-sm font-medium text-muted"
                          >
                            <.icon name="hero-play-circle" class="h-4 w-4 text-primary" />
                            {progress_percent(@progress, @current_lecture)}% watched — completes when
                            you finish the video
                          </p>
                        </div>
                      <% else %>
                        <div class="grid min-h-80 place-items-center bg-white p-8 text-center text-muted">
                          This course does not have any content selected.
                        </div>
                      <% end %>
                    <% end %>
                  </section>
                </div>

                <section
                  :if={@active_section == :module_quiz && is_nil(@active_study_tool)}
                  class="overflow-hidden rounded-3xl bg-white"
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

                      <div id="module-quiz-picker" class="mt-6 grid gap-3 sm:grid-cols-2">
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
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp section_nav_items do
    [
      {:lessons, "Study", "hero-book-open",
       "Watch the lesson and work through the course outline."}
    ]
  end

  # Every downloadable/linked resource in the course, in reading order, for the
  # outline rail's "Resources" tab.
  defp course_resources(course) do
    for module <- course.modules,
        lecture <- module.lectures,
        resource <- lecture.resources,
        do: resource
  end

  # Client-side flip between the outline rail's two tabs — no server round-trip.
  defp switch_outline_tab(:outline) do
    JS.show(to: "#outline-panel")
    |> JS.hide(to: "#resources-panel")
    |> JS.add_class("border-primary text-dark", to: "#outline-tab")
    |> JS.remove_class("border-transparent text-muted", to: "#outline-tab")
    |> JS.add_class("border-transparent text-muted", to: "#resources-tab")
    |> JS.remove_class("border-primary text-dark", to: "#resources-tab")
  end

  defp switch_outline_tab(:resources) do
    JS.show(to: "#resources-panel")
    |> JS.hide(to: "#outline-panel")
    |> JS.add_class("border-primary text-dark", to: "#resources-tab")
    |> JS.remove_class("border-transparent text-muted", to: "#resources-tab")
    |> JS.add_class("border-transparent text-muted", to: "#outline-tab")
    |> JS.remove_class("border-primary text-dark", to: "#outline-tab")
  end

  # Flashcards/Extra practice/Timed quiz moved to the cross-course
  # `WasomiWeb.StudyHubLive` — these render as plain navigation links here,
  # not `@active_section` tabs, pre-scoped to whatever module the learner is
  # currently watching so switching to self-study tools for "this" module
  # stays one click away.
  defp study_hub_nav_items do
    [
      {"flashcards", "Flashcards", "hero-rectangle-stack",
       "Recall key ideas one card at a time."},
      {"timed_quiz", "Smart Test", "hero-clipboard-document-check",
       "Build a timed test for this lesson."},
      {"study_guide", "Study guide", "hero-light-bulb",
       "Short notes on this lesson, in the style you pick."}
    ]
  end

  defp course_nav_tooltip(assigns) do
    ~H"""
    <span class="pointer-events-none absolute left-1/2 top-full z-50 mt-2 hidden w-max max-w-80 -translate-x-1/2 whitespace-normal rounded-lg bg-ink px-3 py-1.5 text-center text-xs font-medium leading-snug text-white shadow-lg group-hover/top-tooltip:block">
      {@label}
    </span>
    """
  end

  defp current_module(%{current_lecture: nil}), do: nil

  defp current_module(%{current_lecture: lecture, course: course}) do
    Enum.find(course.modules, &(&1.id == lecture.module_id))
  end

  defp embedded_study_hub_session(user, course, nil, mode, _resource_id) do
    %{
      "current_user_id" => user.id,
      "course" => course.slug,
      "mode" => mode,
      "embedded" => true
    }
  end

  # Generative study tools always open at the scope chooser. Selecting a module
  # or lesson is an explicit learner action; generation/building follows it.
  defp embedded_study_hub_session(user, course, module, mode, nil) do
    %{
      "current_user_id" => user.id,
      "course" => course.slug,
      "module" => to_string(module.id),
      "mode" => mode,
      "embedded" => true
    }
  end

  # The one exception to opening at the chooser: the learner already chose, by
  # clicking "Study guide" on a specific PDF, so the scope arrives pre-set.
  defp embedded_study_hub_session(user, course, module, mode, resource_id) do
    %{
      "current_user_id" => user.id,
      "course" => course.slug,
      "module" => to_string(module.id),
      "scope" => "resource",
      "resource" => to_string(resource_id),
      "mode" => mode,
      "embedded" => true
    }
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

    read_resource_ids =
      if preview? do
        socket.assigns.preview_read_resource_ids
      else
        Learning.read_resource_ids_for_course(socket.assigns.current_user, course)
      end

    course_progress = Learning.summarize_progress(course, progress)
    unlocked_lecture_ids = unlocked_lecture_ids(socket, lectures, progress, preview?)
    current_lecture = pick_current_lecture(socket, lectures, progress)

    socket
    |> assign(:course_progress, course_progress)
    |> assign(:progress, progress)
    |> assign(:read_resource_ids, read_resource_ids)
    |> assign(:unlocked_lecture_ids, unlocked_lecture_ids)
    |> assign(:current_lecture, current_lecture)
    |> refresh_certificates()
  end

  defp pick_current_lecture(socket, lectures, progress) do
    socket.assigns[:current_lecture] ||
      requested_preview_lecture(socket, lectures) ||
      Enum.find(lectures, &(progress_status(progress, &1.id) != :completed)) ||
      List.last(lectures)
  end

  defp requested_preview_lecture(%{assigns: %{preview?: true}} = socket, lectures) do
    requested_id = socket.assigns.requested_preview_lecture_id
    Enum.find(lectures, &(to_string(&1.id) == requested_id))
  end

  defp requested_preview_lecture(_socket, _lectures), do: nil

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

  defp final_lecture?(course, %{id: lecture_id}) do
    case List.last(course_lectures(course)) do
      %{id: ^lecture_id} -> true
      _ -> false
    end
  end

  defp final_lecture?(_course, _lecture), do: false

  # The admin's own estimate wins when they set one: it can account for the
  # reading, the practice questions and the quizzes, none of which a video
  # duration knows about. Falling back to the video sum keeps the figure that
  # existing courses (with no estimate saved) have always shown.
  # What a lesson costs in time, as far as we can tell: the video's own length
  # when there is one, and otherwise a flat reading allowance per PDF, since a
  # document carries no duration. `nil` means we genuinely don't know, and the
  # UI shows nothing rather than a made-up number.
  @reading_minutes_per_pdf 5

  defp lecture_estimated_minutes(%{duration_seconds: seconds}) when is_integer(seconds),
    do: seconds |> Kernel./(60) |> Float.ceil() |> trunc()

  defp lecture_estimated_minutes(lecture) do
    case Enum.count(lecture.resources, &pdf_resource?/1) do
      0 -> nil
      count -> count * @reading_minutes_per_pdf
    end
  end

  defp lecture_number(course, lecture) do
    course
    |> course_lectures()
    |> Enum.find_index(&(&1.id == lecture.id))
    |> case do
      nil -> lecture.position
      index -> index + 1
    end
  end

  # Admins previewing content just want to sanity-check it, not re-earn
  # access to it lecture by lecture — every lecture and quiz is unlocked
  # unconditionally in preview mode, independent of (unpersisted) preview
  # progress. Real learners keep the sequential gate untouched below.
  defp unlocked_lecture_ids(_socket, lectures, _progress, true = _preview?),
    do: MapSet.new(lectures, & &1.id)

  # Mirrors `Wasomi.Learning.lecture_unlocked?/3`: a lecture only clears the
  # gate for the next one once it is completed *and* its lesson quiz (if the
  # lecture has one with published questions) has been passed.
  defp unlocked_lecture_ids(socket, lectures, progress, false = _preview?) do
    Enum.reduce_while(lectures, MapSet.new(), fn lecture, unlocked ->
      unlocked = MapSet.put(unlocked, lecture.id)

      if progress_status(progress, lecture.id) == :completed and
           lecture_quiz_cleared?(socket.assigns, lecture) do
        {:cont, unlocked}
      else
        {:halt, unlocked}
      end
    end)
  end

  # A lecture with no quiz, or whose quiz has no published questions yet,
  # never blocks anyone — `@ready_lecture_quizzes` only holds the ones that
  # are actually takeable.
  defp lecture_quiz_cleared?(assigns, lecture),
    do: not lecture_quiz_pending?(assigns, lecture)

  # The two outline states worth surfacing per lesson: a takeable quiz the
  # learner has passed, and one they still owe.
  defp lecture_quiz_passed?(assigns, lecture) do
    case Map.get(assigns.ready_lecture_quizzes, lecture.id) do
      nil -> false
      quiz -> MapSet.member?(assigns.passed_lecture_quiz_ids, quiz.id)
    end
  end

  defp lecture_quiz_pending?(assigns, lecture) do
    Map.has_key?(assigns.ready_lecture_quizzes, lecture.id) and
      not lecture_quiz_passed?(assigns, lecture)
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

  # A percentage only means something against a video's length. A lecture with
  # no video has no watched fraction, so it reports 0 rather than dividing by
  # nil — the reading-only lessons the outline now renders would otherwise
  # crash here.
  defp progress_percent(_progress, %{duration_seconds: nil}), do: 0

  defp progress_percent(progress, lecture) do
    progress
    |> progress_position(lecture.id)
    |> Kernel./(lecture.duration_seconds)
    |> Kernel.*(100)
    |> round()
    |> min(100)
  end

  defp load_lq_submissions(socket, lecture) do
    if socket.assigns.preview? do
      %{}
    else
      Catalog.map_lecture_question_submissions(socket.assigns.current_user, lecture)
    end
  end

  # The two course-wide lookups the lesson-quiz gate needs. Kept as assigns
  # rather than re-queried per render so the outline can ask "is this lesson
  # unlocked" for every lecture without an N+1.
  defp assign_lecture_quiz_gating(socket) do
    %{course: course, preview?: preview?} = socket.assigns

    passed_ids =
      if preview? do
        MapSet.new()
      else
        Assessments.passed_lecture_quiz_ids_for_user(socket.assigns.current_user.id, course.id)
      end

    socket
    |> assign(
      :ready_lecture_quizzes,
      Assessments.learner_ready_lecture_quizzes_by_lecture(course.id)
    )
    |> assign(:passed_lecture_quiz_ids, passed_ids)
  end

  # Loads the lesson quiz for whatever lecture is now current, along with the
  # learner's latest attempt so a returning learner sees their score instead
  # of a blank form.
  defp load_lecture_quiz(%{assigns: %{current_lecture: nil}} = socket),
    do: reset_lecture_quiz(socket)

  defp load_lecture_quiz(%{assigns: %{current_lecture: lecture}} = socket) do
    case Map.get(socket.assigns.ready_lecture_quizzes, lecture.id) do
      nil ->
        reset_lecture_quiz(socket)

      quiz ->
        questions = Assessments.list_published_lecture_quiz_questions(quiz)

        latest =
          if socket.assigns.preview? do
            nil
          else
            socket.assigns.current_user
            |> Assessments.list_lecture_quiz_submissions_for_user(quiz)
            |> List.first()
          end

        answers =
          case latest do
            nil ->
              %{}

            submission ->
              Map.new(submission.answers, fn {k, v} -> {to_string(k), v && to_string(v)} end)
          end

        socket
        |> assign(:lecture_quiz, %{quiz: quiz, questions: questions})
        |> assign(:lecture_quiz_answers, answers)
        |> assign(:lecture_quiz_result, latest)
    end
  end

  defp reset_lecture_quiz(socket) do
    socket
    |> assign(:lecture_quiz, nil)
    |> assign(:lecture_quiz_answers, %{})
    |> assign(:lecture_quiz_result, nil)
  end

  # Finishing the video is the moment the quiz matters, so the lesson opens it
  # rather than leaving a graded step sitting in a tab the learner never opened.
  defp focus_pending_quiz(socket, lecture) do
    if lecture_quiz_pending?(socket.assigns, lecture) do
      assign(socket, :lesson_tab, :quiz)
    else
      socket
    end
  end

  # The lesson's sub-navigation. A tab is only offered for material the lecture
  # actually has, and the quiz carries its state in the strip itself — it is what
  # unlocks the next lesson, so it has to advertise itself.
  defp lesson_tabs(assigns) do
    lecture = assigns.current_lecture

    [
      %{id: :overview, label: "Lesson", icon: "hero-book-open", count: nil, flag: nil},
      lecture.questions != [] &&
        %{
          id: :practice,
          label: "Practice",
          icon: "hero-pencil-square",
          count: length(lecture.questions),
          flag: nil
        },
      assigns.lecture_quiz &&
        %{
          id: :quiz,
          label: "Lesson quiz",
          icon: "hero-clipboard-document-check",
          count: length(assigns.lecture_quiz.questions),
          flag: if(lesson_quiz_passed?(assigns, lecture), do: :passed, else: :required)
        }
    ]
    |> Enum.filter(& &1)
  end

  # Persisted passes and the just-submitted attempt both count — the latter is
  # all preview mode has, since nothing is written there.
  defp lesson_quiz_passed?(assigns, lecture) do
    lecture_quiz_passed?(assigns, lecture) or
      match?(%{passed: true}, assigns.lecture_quiz_result)
  end

  # Completing a lecture no longer unlocks the next one on its own when the
  # lesson has a quiz to pass, so don't promise an unlock that didn't happen.
  defp lecture_completed_flash(socket, lecture) do
    if lecture_quiz_cleared?(socket.assigns, lecture) do
      "Lecture completed. The next lesson is now unlocked."
    else
      "Lecture completed. Pass this lesson's quiz to unlock the next lesson."
    end
  end

  defp submit_lecture_quiz(socket, quiz, answers) do
    case Assessments.submit_lecture_quiz(socket.assigns.current_user, quiz, answers) do
      {:ok, submission} ->
        passed_ids =
          if submission.passed,
            do: MapSet.put(socket.assigns.passed_lecture_quiz_ids, quiz.id),
            else: socket.assigns.passed_lecture_quiz_ids

        flash =
          if submission.passed,
            do: {:info, "Lesson quiz passed — #{submission.score_percent}%."},
            else:
              {:error,
               "You scored #{submission.score_percent}%. " <>
                 "#{quiz.passing_score_percent}% is needed to move on — try again."}

        {kind, message} = flash

        {:noreply,
         socket
         |> assign(:lecture_quiz_result, submission)
         |> assign(:passed_lecture_quiz_ids, passed_ids)
         |> refresh_progress()
         |> put_flash(kind, message)}

      {:error, :quiz_not_ready} ->
        {:noreply, put_flash(socket, :error, "This quiz is not ready for submission.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not submit quiz.")}
    end
  end

  defp lq_feedback_band(score) when score >= 0.8,
    do: %{label: "Great answer!", class: "bg-green-50 text-green-700"}

  defp lq_feedback_band(score) when score >= 0.5,
    do: %{label: "Close enough — good thinking!", class: "bg-amber-50 text-amber-700"}

  defp lq_feedback_band(_score),
    do: %{label: "Needs work — see the model answer below.", class: "bg-red-50 text-red-700"}

  # ── Resources ──────────────────────────────────────────────────────────────

  # Scoped to the lecture on screen rather than the whole course: the only
  # resources a learner can act on are the ones they can currently see, so a
  # forged resource_id for a locked lesson finds nothing here.
  defp find_current_resource(socket, resource_id) do
    case socket.assigns.current_lecture do
      nil -> nil
      lecture -> Enum.find(lecture.resources, &(to_string(&1.id) == to_string(resource_id)))
    end
  end

  defp resource_read?(read_resource_ids, resource),
    do: MapSet.member?(read_resource_ids, resource.id)

  # Reading the last outstanding PDF on a lecture with no video completes it, so
  # say so rather than leaving the learner to notice the outline changed.
  defp resource_read_flash(socket, _resource) do
    lecture = socket.assigns.current_lecture

    if is_nil(lecture.duration_seconds) and
         all_pdfs_read?(socket.assigns.read_resource_ids, lecture) do
      "Marked as read — that was the last one, so this lesson is complete."
    else
      "Marked as read."
    end
  end

  defp lecture_pdfs(lecture), do: Enum.filter(lecture.resources, &pdf_resource?/1)

  defp all_pdfs_read?(read_resource_ids, lecture) do
    pdfs = lecture_pdfs(lecture)
    pdfs != [] and Enum.all?(pdfs, &resource_read?(read_resource_ids, &1))
  end

  defp unread_pdf_count(read_resource_ids, lecture) do
    lecture
    |> lecture_pdfs()
    |> Enum.count(&(not resource_read?(read_resource_ids, &1)))
  end

  # A lesson whose only material is reading: nothing to watch, so its PDFs are
  # what completes it.
  defp reading_only_lecture?(lecture),
    do: is_nil(lecture.duration_seconds) and lecture_pdfs(lecture) != []

  # The distinct kinds of material a lesson carries, for the outline's badges —
  # so a learner can see at a glance whether a lesson is a video, a reading, or
  # both, before they open it.
  defp resource_type_badges(assigns, lecture) do
    pdf_count = length(lecture_pdfs(lecture))
    link_count = Enum.count(lecture.resources, &(&1.kind == :link))

    [
      lecture.duration_seconds && %{icon: "hero-play-circle", label: "Video"},
      pdf_count > 0 &&
        %{
          icon: "hero-document-text",
          label: if(pdf_count == 1, do: "PDF", else: "#{pdf_count} PDFs")
        },
      link_count > 0 && %{icon: "hero-link", label: "Link"},
      lecture.questions != [] && %{icon: "hero-pencil-square", label: "Practice"},
      Map.has_key?(assigns.ready_lecture_quizzes, lecture.id) &&
        %{icon: "hero-clipboard-document-check", label: "Quiz"}
    ]
    |> Enum.filter(& &1)
  end

  # What is still outstanding on a lesson, in one sentence, for the outline's
  # hover tooltip. `nil` for a lesson with nothing left to do — there is then no
  # tooltip to show.
  defp lecture_todo_hint(assigns, lecture) do
    %{progress: progress, read_resource_ids: read_resource_ids} = assigns
    completed? = progress_status(progress, lecture.id) == :completed

    cond do
      not lecture_unlocked?(assigns.unlocked_lecture_ids, lecture.id) ->
        "Locked — finish the lesson before it to unlock this one."

      completed? and lecture_quiz_pending?(assigns, lecture) ->
        "Take the lesson quiz — you need to pass it to unlock the next lesson."

      completed? ->
        nil

      reading_only_lecture?(lecture) ->
        case unread_pdf_count(read_resource_ids, lecture) do
          0 -> "Open this lesson to finish it."
          1 -> "1 PDF left to read — mark it as read to complete this lesson."
          count -> "#{count} PDFs left to read — mark each as read to complete this lesson."
        end

      is_nil(lecture.duration_seconds) ->
        "Open this lesson and mark it complete."

      progress_status(progress, lecture.id) == :in_progress ->
        "#{progress_percent(progress, lecture)}% watched — it completes on its own once you " <>
          "finish the video."

      true ->
        "Not started — watch the video and it completes on its own."
    end
  end
end
