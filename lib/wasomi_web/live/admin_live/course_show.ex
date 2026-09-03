defmodule WasomiWeb.AdminLive.CourseShow do
  use WasomiWeb, :live_view

  alias Wasomi.{Accounts, Assessments, Catalog, Enrollments, Learning, Payments}
  alias Wasomi.Catalog.Analytics
  alias Wasomi.Catalog.{CourseModule, Lecture}
  alias Wasomi.Catalog.PublishGuard
  alias WasomiWeb.CourseLive
  alias WasomiWeb.CourseModuleLive
  alias WasomiWeb.LectureLive

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    {:ok,
     socket
     |> assign(:modal, nil)
     |> assign(:course_module, nil)
     |> assign(:lecture, nil)
     |> assign(:grant_access_form, nil)
     |> assign(:selected_grant_learner_ids, [])
     |> assign(:quiz_lecture_id, nil)
     |> assign(:quiz_modal_tab, :generate)
     |> assign(:form_title, nil)
     |> assign(:active_tab, :curriculum)
     |> assign(:deleting_quiz, nil)
     |> assign(:deleting_module, nil)
     |> assign(:deleting_lecture, nil)
     |> assign(:collapsed_modules, MapSet.new())
     |> assign(:publish_checklist, nil)
     |> assign(:confirming_unpublish?, false)
     |> load_course(slug)}
  end

  # push_patch from the module/lecture form components lands here; reload and
  # close any open modal.
  @impl true
  def handle_params(%{"slug" => slug} = params, _url, socket) do
    active_tab = course_detail_tab(params["tab"], socket.assigns[:active_tab] || :curriculum)

    {:noreply,
     socket
     |> assign(:active_tab, active_tab)
     |> load_course(slug)
     |> close_modal()}
  end

  @impl true
  def handle_event("edit_course", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal, :course)
     |> assign(:form_title, "Edit course")}
  end

  def handle_event("open_grant_access", _params, socket) do
    if Catalog.grant_access_allowed?(socket.assigns.course) do
      {:noreply,
       socket
       |> assign(:modal, :grant_access)
       |> assign(
         :grant_access_form,
         to_form(Enrollments.change_grant_access(%{"course_id" => socket.assigns.course.id}))
       )
       |> assign(:selected_grant_learner_ids, [])}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "Publish this course or mark it internal before granting access."
       )}
    end
  end

  def handle_event("validate_grant_access", params, socket) do
    form_params = Map.get(params, "grant_access_form", %{})
    selected_learner_ids = selected_learner_ids(params)

    form =
      form_params
      |> Map.put("course_id", socket.assigns.course.id)
      |> Enrollments.change_grant_access()
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply,
     socket
     |> assign(:grant_access_form, form)
     |> assign(:selected_grant_learner_ids, selected_learner_ids)}
  end

  def handle_event(
        "grant_access",
        %{"learner_ids" => learner_ids, "grant_access_form" => params},
        socket
      ) do
    params = Map.put(params, "course_id", socket.assigns.course.id)
    selected_learners = find_grantable_learners(socket.assigns.grantable_learners, learner_ids)

    if selected_learners == [] do
      {:noreply,
       socket
       |> put_flash(:error, "Choose at least one learner who does not already have access.")
       |> assign(
         :grant_access_form,
         to_form(Enrollments.change_grant_access(params), action: :validate)
       )}
    else
      grant_access_to_learners(socket, selected_learners, params)
    end
  end

  def handle_event("grant_access", %{"grant_access_form" => params}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Choose at least one learner who does not already have access.")
     |> assign(
       :grant_access_form,
       to_form(
         Enrollments.change_grant_access(Map.put(params, "course_id", socket.assigns.course.id)),
         action: :validate
       )
     )
     |> assign(:selected_grant_learner_ids, [])}
  end

  def handle_event("publish_course", _params, socket) do
    case Catalog.publish_course(socket.assigns.course) do
      {:ok, course} ->
        {:noreply,
         socket
         |> put_flash(:info, published_flash(course))
         |> load_course(course.slug)}

      {:error, issues} when is_list(issues) ->
        checklist =
          socket.assigns.course.id
          |> Catalog.get_course_with_outline!()
          |> PublishGuard.checklist()

        {:noreply, assign(socket, :publish_checklist, checklist)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Could not publish this course.")}
    end
  end

  def handle_event("close_publish_checklist", _params, socket) do
    {:noreply, assign(socket, :publish_checklist, nil)}
  end

  def handle_event("confirm_unpublish_course", _params, socket) do
    {:noreply, assign(socket, :confirming_unpublish?, true)}
  end

  def handle_event("cancel_unpublish_course", _params, socket) do
    {:noreply, assign(socket, :confirming_unpublish?, false)}
  end

  def handle_event("unpublish_course", _params, socket) do
    {:ok, course} = Catalog.unpublish_course(socket.assigns.course)

    {:noreply,
     socket
     |> put_flash(:info, "Course unpublished — it's no longer visible in the public catalog.")
     |> assign(:confirming_unpublish?, false)
     |> load_course(course.slug)}
  end

  def handle_event("new_module", _params, socket) do
    course = socket.assigns.course

    {:noreply,
     socket
     |> assign(:modal, :module)
     |> assign(:form_title, "New module")
     |> assign(:course_module, %CourseModule{
       course_id: course.id,
       position: length(course.modules) + 1
     })}
  end

  def handle_event("edit_module", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:modal, :module)
     |> assign(:form_title, "Edit module")
     |> assign(:course_module, Catalog.get_course_module!(id))}
  end

  def handle_event("new_lecture", %{"module-id" => module_id}, socket) do
    module_id = to_int(module_id)
    module = Enum.find(socket.assigns.course.modules, &(&1.id == module_id))

    {:noreply,
     socket
     |> assign(:modal, :lecture)
     |> assign(:form_title, "New lecture")
     |> assign(:lecture, %Lecture{
       module_id: module.id,
       position: length(module.lectures) + 1
     })}
  end

  def handle_event("edit_lecture", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:modal, :lecture)
     |> assign(:form_title, "Edit lecture")
     |> assign(:lecture, Catalog.get_lecture!(id))}
  end

  def handle_event("close_modal", _params, socket) do
    socket =
      if socket.assigns.modal == :quiz do
        load_course(socket, socket.assigns.course.slug)
      else
        socket
      end

    {:noreply, close_modal(socket)}
  end

  def handle_event("open_quiz", %{"id" => id} = params, socket) do
    tab = if params["tab"] == "questions", do: :questions, else: :generate

    {:noreply,
     socket
     |> assign(:modal, :quiz)
     |> assign(:quiz_lecture_id, id)
     |> assign(:quiz_modal_tab, tab)}
  end

  def handle_event("toggle_module", %{"id" => id}, socket) do
    id = to_int(id)
    collapsed = socket.assigns.collapsed_modules

    collapsed =
      if MapSet.member?(collapsed, id),
        do: MapSet.delete(collapsed, id),
        else: MapSet.put(collapsed, id)

    {:noreply, assign(socket, :collapsed_modules, collapsed)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket)
      when tab in ["curriculum", "students"] do
    {:noreply, assign(socket, :active_tab, course_detail_tab(tab, socket.assigns.active_tab))}
  end

  def handle_event("generate_quiz", %{"module-id" => module_id}, socket) do
    module = Enum.find(socket.assigns.course.modules, &(to_string(&1.id) == to_string(module_id)))

    if module_ready_for_quiz_generation?(module, socket.assigns.lecture_quiz_question_counts) do
      quiz =
        Assessments.get_quiz_for_module(module) ||
          with {:ok, quiz} <- Assessments.create_quiz(module, %{title: "#{module.title} Quiz"}) do
            quiz
          end

      case quiz do
        %Assessments.Quiz{id: quiz_id} ->
          course_slug = socket.assigns.course.slug

          {:noreply,
           push_navigate(socket, to: ~p"/admin/courses/#{course_slug}/quizzes/#{quiz_id}/edit")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not create a quiz for this module.")}
      end
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "Generate a quiz for every lecture in this module before generating the module quiz."
       )}
    end
  end

  def handle_event("confirm_delete_quiz", %{"id" => id}, socket) do
    {:noreply, assign(socket, :deleting_quiz, Assessments.get_quiz!(id))}
  end

  def handle_event("cancel_delete_quiz", _params, socket) do
    {:noreply, assign(socket, :deleting_quiz, nil)}
  end

  def handle_event("delete_quiz", %{"id" => id}, socket) do
    quiz = Assessments.get_quiz!(id)
    {:ok, _deleted} = Assessments.delete_quiz(quiz)

    {:noreply,
     socket
     |> put_flash(:info, "Quiz deleted.")
     |> assign(:deleting_quiz, nil)
     |> load_course(socket.assigns.course.slug)}
  end

  def handle_event("confirm_delete_module", %{"id" => id}, socket) do
    {:noreply, assign(socket, :deleting_module, Catalog.get_course_module!(id))}
  end

  def handle_event("cancel_delete_module", _params, socket) do
    {:noreply, assign(socket, :deleting_module, nil)}
  end

  def handle_event("delete_module", %{"id" => id}, socket) do
    module = Catalog.get_course_module!(id)
    {:ok, _} = Catalog.delete_course_module(module)

    {:noreply,
     socket
     |> put_flash(:info, "Module deleted.")
     |> assign(:deleting_module, nil)
     |> load_course(socket.assigns.course.slug)}
  end

  def handle_event("confirm_delete_lecture", %{"id" => id}, socket) do
    {:noreply, assign(socket, :deleting_lecture, Catalog.get_lecture!(id))}
  end

  def handle_event("cancel_delete_lecture", _params, socket) do
    {:noreply, assign(socket, :deleting_lecture, nil)}
  end

  def handle_event("delete_lecture", %{"id" => id}, socket) do
    lecture = Catalog.get_lecture!(id)
    {:ok, _} = Catalog.delete_lecture(lecture)

    {:noreply,
     socket
     |> put_flash(:info, "Lecture deleted.")
     |> assign(:deleting_lecture, nil)
     |> load_course(socket.assigns.course.slug)}
  end

  def handle_event("reorder_modules", %{"module_ids" => module_ids}, socket) do
    case Catalog.reorder_course_modules(socket.assigns.course.id, module_ids) do
      {:ok, _} ->
        {:noreply, load_course(socket, socket.assigns.course.slug)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not reorder modules. Refresh and try again.")}
    end
  end

  def handle_event(
        "reorder_lectures",
        %{"module_id" => module_id, "lecture_ids" => lecture_ids},
        socket
      ) do
    case Catalog.reorder_module_lectures(module_id, lecture_ids) do
      {:ok, _} ->
        {:noreply, load_course(socket, socket.assigns.course.slug)}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not reorder lectures. Refresh and try again.")}
    end
  end

  @impl true
  def handle_info({LectureLive.FormComponent, {:content_saved, _lecture}}, socket) do
    {:noreply, load_course(socket, socket.assigns.course.slug)}
  end

  def handle_info({mod, {:saved, _record}}, socket)
      when mod in [
             CourseLive.FormComponent,
             CourseModuleLive.FormComponent,
             LectureLive.FormComponent
           ] do
    {:noreply, socket |> load_course(socket.assigns.course.slug) |> close_modal()}
  end

  def handle_info({:email, _email}, socket), do: {:noreply, socket}

  defp close_modal(socket) do
    assign(socket,
      modal: nil,
      course_module: nil,
      lecture: nil,
      grant_access_form: nil,
      selected_grant_learner_ids: [],
      quiz_lecture_id: nil,
      form_title: nil
    )
  end

  defp published_flash(%{is_internal: true}) do
    "Course published. It is internal, so learners still need granted access."
  end

  defp published_flash(_course), do: "Course published — it's now visible in the public catalog."

  defp load_course(socket, slug) do
    course = Catalog.get_course_by_slug!(slug)
    enrollments = Enrollments.list_active_for_course(course.id)
    payments = Payments.list_payments_for_course(course.id)

    paid_by_user =
      payments
      |> Enum.filter(&(&1.status == :successful))
      |> Map.new(&{&1.user_id, &1})

    completion_percent_by_user = Learning.completion_percent_by_user(course)
    quiz_scores_by_user = Assessments.latest_quiz_scores_by_user(course.id)

    students =
      Enum.map(enrollments, fn enrollment ->
        %{
          enrollment: enrollment,
          payment: Map.get(paid_by_user, enrollment.user_id),
          completion_percent: Map.get(completion_percent_by_user, enrollment.user_id, 0),
          quiz_scores: Map.get(quiz_scores_by_user, enrollment.user_id, [])
        }
      end)

    enrolled_user_ids = MapSet.new(enrollments, & &1.user_id)

    grantable_learners =
      Accounts.list_users(role: :learner)
      |> Enum.reject(&MapSet.member?(enrolled_user_ids, &1.id))

    lecture_count = Enum.sum(Enum.map(course.modules, &length(&1.lectures)))

    # Course analytics
    funnel = Analytics.funnel(course_id: course.id)
    module_completion_rates = Analytics.module_completion_rates(course_id: course.id)
    quiz_scores = Analytics.average_quiz_scores(course_id: course.id)
    video_dropoffs = Analytics.video_dropoff_seconds(course_id: course.id)
    monthly_rev = Analytics.monthly_revenue(course_id: course.id)

    overall_completion_rate =
      Map.get(Analytics.completion_rate_by_course(course_id: course.id), course.id, 0)

    quiz_pass_rate =
      Map.get(Analytics.quiz_pass_rate_by_course(course_id: course.id), course.id, 0)

    module_analytics_rows =
      Enum.map(course.modules, fn module ->
        completion = Map.get(module_completion_rates, module.id)
        quiz = Map.get(quiz_scores, module.id)

        %{
          module_id: module.id,
          title: module.title,
          completion_percent: (completion && completion.rate_percent) || 0,
          remaining_learners: (completion && completion.completed_learners) || 0,
          quiz_score_percent: (quiz && round(quiz.average_score_percent)) || nil,
          submissions: (quiz && quiz.submissions) || 0
        }
      end)

    funnel_steps =
      funnel
      |> Enum.with_index()
      |> Enum.map(fn {%{count: count} = step, index} ->
        previous_count = index > 0 && Enum.at(funnel, index - 1).count

        Map.merge(step, %{
          percent_of_previous: previous_count && percent(count, previous_count),
          last?: index == length(funnel) - 1
        })
      end)

    funnel_overall_conversion =
      case funnel do
        [%{count: 0} | _] -> nil
        steps -> percent(List.last(steps).count, hd(steps).count)
      end

    revenue_chart =
      Enum.map(monthly_rev, fn %{month: month, revenue_minor: revenue_minor} ->
        %{
          label: Calendar.strftime(month, "%b %Y"),
          value: revenue_minor,
          value_label: compact_revenue_label(revenue_minor),
          tooltip: Payments.format_minor(revenue_minor, course.currency)
        }
      end)

    avg_quiz_score =
      module_analytics_rows
      |> Enum.map(& &1.quiz_score_percent)
      |> Enum.filter(& &1)
      |> case do
        [] -> nil
        scores -> round(Enum.sum(scores) / length(scores))
      end

    socket
    |> assign(:page_title, course.title)
    |> assign(:course, course)
    |> assign(:channel_stats, Wasomi.Channels.stats_for_course(course))
    |> assign(:review_summary, Wasomi.Reviews.course_review_summary(course.id))
    |> assign(:reviews, Wasomi.Reviews.list_course_reviews(course.id))
    |> assign(:students, students)
    |> assign(:student_count, length(enrollments))
    |> assign(:grantable_learners, grantable_learners)
    |> assign(:lecture_count, lecture_count)
    |> assign(:revenue_minor, Payments.revenue_minor_for_course(course.id))
    |> assign(:draft_question_counts, Assessments.count_draft_questions_by_module(course.id))
    |> assign(
      :published_question_counts,
      Assessments.count_published_questions_by_module(course.id)
    )
    |> assign(:quizzes_by_module, Assessments.get_quizzes_by_module(course.id))
    |> assign(
      :lecture_quiz_question_counts,
      Assessments.count_lecture_quiz_questions_by_lecture(course.id)
    )
    |> assign(:analytics_funnel, funnel_steps)
    |> assign(:analytics_funnel_conversion, funnel_overall_conversion)
    |> assign(:analytics_module_rows, module_analytics_rows)
    |> assign(:analytics_video_dropoffs, video_dropoffs)
    |> assign(:analytics_revenue_chart, revenue_chart)
    |> assign(:analytics_completion_rate, overall_completion_rate)
    |> assign(:analytics_quiz_pass_rate, quiz_pass_rate)
    |> assign(:analytics_avg_quiz_score, avg_quiz_score)
  end

  defp module_ready_for_quiz_generation?(module, lecture_quiz_question_counts) do
    Enum.all?(module.lectures, &Map.has_key?(lecture_quiz_question_counts, &1.id))
  end

  defp selected_learner_ids(params) do
    params
    |> Map.get("learner_ids", [])
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp find_grantable_learners(learners, learner_ids) do
    selected_ids = MapSet.new(List.wrap(learner_ids), &to_string/1)
    Enum.filter(learners, &MapSet.member?(selected_ids, to_string(&1.id)))
  end

  defp learner_selected?(learner, selected_learner_ids) do
    to_string(learner.id) in selected_learner_ids
  end

  defp selected_learner_label(learners, selected_learner_ids) do
    learners
    |> find_grantable_learners(selected_learner_ids)
    |> Enum.map(&(&1.name || &1.email))
    |> case do
      [] ->
        "Select learners"

      names ->
        visible_names = Enum.take(names, 4)
        remaining_count = length(names) - length(visible_names)

        case remaining_count do
          0 -> Enum.join(visible_names, ", ")
          count -> "#{Enum.join(visible_names, ", ")} +#{count} more"
        end
    end
  end

  defp grant_access_to_learners(socket, learners, params) do
    learners
    |> Enum.reduce_while({:ok, 0}, fn learner, {:ok, count} ->
      case Enrollments.grant_access(learner, socket.assigns.current_user, params) do
        {:ok, _enrollment} -> {:cont, {:ok, count + 1}}
        {:error, failure} -> {:halt, {:error, failure}}
      end
    end)
    |> case do
      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(:info, grant_access_success_message(count))
         |> load_course(socket.assigns.course.slug)
         |> close_modal()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :grant_access_form, to_form(changeset, action: :validate))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to grant course access.")}
    end
  end

  defp grant_access_success_message(1) do
    "Access granted. The learner has been notified by email and in-app."
  end

  defp grant_access_success_message(count) do
    "Access granted to #{count} learners. They have been notified by email and in-app."
  end

  defp grant_access_button_label([]), do: "Grant access"

  defp grant_access_button_label([_learner_id]), do: "Grant access to 1 learner"

  defp grant_access_button_label(learner_ids) do
    "Grant access to #{length(learner_ids)} learners"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:courses} current_user={@current_user}>
      <div class="w-full space-y-5 px-5 py-8 lg:px-8">
        <.link
          navigate={~p"/admin/courses"}
          class="inline-flex items-center gap-1.5 text-sm font-medium text-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left-mini" class="h-4 w-4" /> Back to courses
        </.link>

        <%!-- Hero --%>
        <section class="overflow-hidden rounded-[32px] border border-black/5 bg-gradient-to-b from-mint via-white to-white">
          <div class="grid gap-8 p-6 lg:grid-cols-2 lg:items-center lg:p-10">
            <div>
              <div class="flex items-center gap-3">
                <span class="text-sm font-semibold uppercase tracking-wider text-primary">
                  Course
                </span>
                <.status_badge status={@course.status} />
                <span
                  :if={@course.is_internal}
                  class="inline-flex items-center rounded-full bg-soft px-2.5 py-1 text-xs font-semibold text-ink"
                >
                  Internal
                </span>
              </div>
              <h1 class="mt-4 text-3xl font-semibold leading-tight text-ink sm:text-4xl">
                {@course.title}
              </h1>
              <p class="mt-4 max-w-xl text-body">{@course.description}</p>

              <div class="mt-6 flex flex-wrap items-center gap-3">
                <button
                  :if={@course.status == :draft}
                  type="button"
                  phx-click={JS.push("publish_course")}
                  class="group inline-flex items-center gap-2 rounded-full bg-primary py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-ink"
                >
                  Publish course
                  <span class="grid h-9 w-9 place-items-center rounded-full bg-white/20 text-white transition group-hover:bg-primary">
                    <.icon name="hero-rocket-launch" class="h-4 w-4" />
                  </span>
                </button>
                <button
                  :if={@course.status == :published}
                  type="button"
                  phx-click={JS.push("confirm_unpublish_course")}
                  class="inline-flex items-center gap-2 rounded-full border border-ink px-5 py-2.5 text-sm font-medium text-ink transition hover:bg-ink hover:text-white"
                >
                  <.icon name="hero-eye-slash" class="h-4 w-4" /> Unpublish
                </button>
                <button
                  type="button"
                  phx-click={JS.push("edit_course")}
                  class="group inline-flex items-center gap-2 rounded-full bg-ink py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
                >
                  Edit course
                  <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover:bg-ink">
                    <.icon name="hero-pencil-square" class="h-4 w-4" />
                  </span>
                </button>
                <.link
                  :if={Catalog.catalog_visible?(@course)}
                  href={~p"/courses/#{@course.slug}"}
                  target="_blank"
                  class="inline-flex items-center gap-2 rounded-full border border-ink px-5 py-2.5 text-sm font-medium text-ink transition hover:bg-ink hover:text-white"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" /> View public page
                </.link>
                <.link
                  navigate={~p"/admin/courses/#{@course.slug}/preview"}
                  class="inline-flex items-center gap-2 rounded-full border border-ink px-5 py-2.5 text-sm font-medium text-ink transition hover:bg-ink hover:text-white"
                >
                  <.icon name="hero-eye" class="h-4 w-4" /> Preview course
                </.link>
                <.link
                  navigate={~p"/admin/courses/#{@course.slug}/certificate"}
                  class="inline-flex items-center gap-2 rounded-full border border-ink px-5 py-2.5 text-sm font-medium text-ink transition hover:bg-ink hover:text-white"
                >
                  <.icon name="hero-academic-cap" class="h-4 w-4" /> Certificate
                </.link>
              </div>
            </div>

            <div class="overflow-hidden rounded-[28px] border border-black/5 bg-white shadow-2xl">
              <img src={@course.thumbnail_key} alt="" class="h-64 w-full object-cover lg:h-80" />
              <div class="flex items-center justify-between gap-4 p-6">
                <div>
                  <p class="text-sm text-muted">One-time course fee</p>
                  <p class="text-2xl font-semibold text-ink">{Catalog.format_price(@course)}</p>
                </div>
                <div :if={!@course.is_free} class="text-right">
                  <p class="text-sm text-muted">Revenue to date</p>
                  <p class="text-2xl font-semibold text-primary">
                    {Payments.format_minor(@revenue_minor, @course.currency)}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </section>

        <%!-- Stats --%>
        <div class={[
          "grid gap-5 sm:grid-cols-2",
          if(@course.is_free, do: "lg:grid-cols-3", else: "xl:grid-cols-4")
        ]}>
          <.stat_card label="Students" value={@student_count} icon="hero-users" />
          <.stat_card
            :if={!@course.is_free}
            label="Revenue"
            value={Payments.format_minor(@revenue_minor, @course.currency)}
            icon="hero-banknotes"
          />
          <.stat_card label="Modules" value={length(@course.modules)} icon="hero-rectangle-stack" />
          <.stat_card label="Lectures" value={@lecture_count} icon="hero-play-circle" />
        </div>

        <%!-- Cohort channel --%>
        <section class="flex flex-wrap items-center justify-between gap-4 rounded-3xl border border-black/5 bg-white p-6 shadow-card">
          <div class="flex items-center gap-3">
            <span class="grid h-11 w-11 shrink-0 place-items-center rounded-2xl bg-mint text-primary">
              <.icon name="hero-chat-bubble-left-right" class="h-5 w-5" />
            </span>
            <div>
              <p class="text-sm font-semibold text-ink">Cohort channel</p>
              <p class="text-xs text-body">
                {@channel_stats.message_count}
                {ngettext("message", "messages", @channel_stats.message_count)}
                <span :if={@channel_stats.last_activity_at}>
                  · last activity {format_channel_time(@channel_stats.last_activity_at)}
                </span>
              </p>
            </div>
          </div>
          <.link
            navigate={~p"/admin/discussions?#{%{course: @course.slug}}"}
            class="inline-flex items-center gap-2 rounded-full border border-ink px-4 py-2 text-sm font-medium text-ink transition hover:bg-ink hover:text-white"
          >
            <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" /> Open channel
          </.link>
        </section>

        <%!-- Tabs --%>
        <div
          id="course-detail-tabs"
          role="tablist"
          aria-label="Course details"
          class="grid grid-cols-3 overflow-hidden rounded-2xl border border-black/5 bg-surface p-1"
        >
          <.link
            id="curriculum-tab"
            patch={~p"/admin/courses/#{@course.slug}?#{%{tab: "curriculum"}}"}
            role="tab"
            aria-selected={to_string(@active_tab == :curriculum)}
            aria-controls="curriculum-panel"
            class={[
              "rounded-xl py-2.5 text-center text-sm font-medium transition",
              if(@active_tab == :curriculum,
                do: "bg-ink text-white",
                else: "text-body hover:text-ink"
              )
            ]}
          >
            Curriculum
          </.link>
          <.link
            id="students-tab"
            patch={~p"/admin/courses/#{@course.slug}?#{%{tab: "students"}}"}
            role="tab"
            aria-selected={to_string(@active_tab == :students)}
            aria-controls="students-panel"
            class={[
              "rounded-xl py-2.5 text-center text-sm font-medium transition",
              if(@active_tab == :students,
                do: "bg-ink text-white",
                else: "text-body hover:text-ink"
              )
            ]}
          >
            Enrolled students
            <span class={[
              "ml-1.5 font-bold",
              if(@active_tab == :students, do: "text-white", else: "text-primary")
            ]}>
              {@student_count}
            </span>
          </.link>
          <.link
            id="analytics-tab"
            patch={~p"/admin/courses/#{@course.slug}?#{%{tab: "analytics"}}"}
            role="tab"
            aria-selected={to_string(@active_tab == :analytics)}
            aria-controls="analytics-panel"
            class={[
              "rounded-xl py-2.5 text-center text-sm font-medium transition",
              if(@active_tab == :analytics,
                do: "bg-ink text-white",
                else: "text-body hover:text-ink"
              )
            ]}
          >
            Analytics
          </.link>
        </div>

        <%!-- Curriculum (editable) --%>
        <section
          :if={@active_tab == :curriculum}
          id="curriculum-panel"
          role="tabpanel"
          aria-labelledby="curriculum-tab"
          class="rounded-3xl border border-black/5 bg-white p-6 shadow-card lg:p-8"
        >
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div>
              <h2 class="text-2xl font-bold text-ink">Course curriculum</h2>
              <p class="mt-1 text-sm text-muted">
                Use the drag handles to reorder modules or move lectures between modules.
              </p>
            </div>
            <button
              type="button"
              phx-click="new_module"
              class="inline-flex items-center gap-2 rounded-full bg-ink px-5 py-3 text-sm font-semibold text-white transition hover:bg-primary"
            >
              <.icon name="hero-plus-mini" class="h-4 w-4" /> Add module
            </button>
          </div>

          <div
            :if={@course.modules != []}
            id="course-modules"
            phx-hook="SortableList"
            data-event="reorder_modules"
            data-order-key="module_ids"
            class="mt-6 space-y-4"
          >
            <article
              :for={module <- @course.modules}
              id={"module-#{module.id}"}
              data-sortable-item
              data-id={module.id}
              draggable="false"
              class="rounded-xl border border-black/10 bg-surface/30 p-5 transition data-[dragging=true]:opacity-60 data-[drag-over=true]:border-primary data-[drag-over=true]:bg-mint/50"
            >
              <div class="flex items-start gap-4">
                <button
                  type="button"
                  data-sortable-handle
                  class="mt-0.5 grid h-9 w-9 shrink-0 cursor-grab place-items-center rounded-xl border border-black/10 bg-white text-ink transition hover:border-primary hover:text-primary active:cursor-grabbing"
                  title="Drag module"
                  aria-label="Drag module"
                >
                  <.icon name="hero-ellipsis-vertical" class="h-4 w-4" />
                </button>
                <button
                  type="button"
                  phx-click={JS.push("toggle_module", value: %{id: module.id})}
                  class="mt-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-full border border-ink text-ink transition hover:bg-ink hover:text-white"
                  title="Toggle module"
                  aria-label="Toggle module"
                >
                  <.icon
                    name={
                      if(MapSet.member?(@collapsed_modules, module.id),
                        do: "hero-chevron-right",
                        else: "hero-chevron-down"
                      )
                    }
                    class="h-4 w-4"
                  />
                </button>
                <span class="mt-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-full border border-primary/20 bg-mint font-semibold text-primary">
                  {module.position}
                </span>
                <div class="min-w-0 flex-1">
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <h3 class="text-lg font-semibold text-ink">{module.title}</h3>
                      <p :if={module.description} class="mt-1 text-sm text-body">
                        {module.description}
                      </p>
                    </div>
                    <div class="flex shrink-0 items-center gap-2">
                      <button
                        type="button"
                        phx-click={JS.push("edit_module", value: %{id: module.id})}
                        class="grid h-9 w-9 place-items-center rounded-full border border-black/10 bg-white text-muted transition hover:border-primary hover:text-primary"
                        title="Edit module"
                      >
                        <.icon name="hero-pencil-square" class="h-4 w-4" />
                      </button>
                      <button
                        type="button"
                        phx-click={JS.push("confirm_delete_module", value: %{id: module.id})}
                        class="grid h-9 w-9 place-items-center rounded-full border border-black/10 bg-white text-muted transition hover:border-red-400 hover:text-red-500"
                        title="Delete module"
                      >
                        <.icon name="hero-trash" class="h-4 w-4" />
                      </button>
                    </div>
                  </div>

                  <div :if={!MapSet.member?(@collapsed_modules, module.id)}>
                    <ul
                      id={"module-#{module.id}-lectures"}
                      phx-hook="SortableList"
                      data-event="reorder_lectures"
                      data-parent-key="module_id"
                      data-parent-id={module.id}
                      data-order-key="lecture_ids"
                      class="mt-4 space-y-2.5"
                    >
                      <li
                        :for={lecture <- module.lectures}
                        id={"lecture-#{lecture.id}"}
                        data-sortable-item
                        data-id={lecture.id}
                        draggable="false"
                        class="flex items-center justify-between gap-3 rounded-lg border border-black/5 bg-white px-4 py-3 transition data-[dragging=true]:opacity-60 data-[drag-over=true]:border-primary data-[drag-over=true]:bg-mint/50"
                      >
                        <span class="flex min-w-0 items-center gap-3">
                          <button
                            type="button"
                            data-sortable-handle
                            class="grid h-8 w-8 shrink-0 cursor-grab place-items-center rounded-lg border border-black/10 text-muted transition hover:border-primary hover:text-primary active:cursor-grabbing"
                            title="Drag lecture"
                            aria-label="Drag lecture"
                          >
                            <.icon name="hero-ellipsis-vertical" class="h-4 w-4" />
                          </button>
                          <.link
                            navigate={
                              ~p"/admin/courses/#{@course.slug}/preview?#{%{lecture_id: lecture.id}}"
                            }
                            class="grid h-8 w-8 shrink-0 place-items-center rounded-full border border-primary/40 text-primary transition hover:bg-primary hover:text-white"
                            title={"Preview #{lecture.title}"}
                            aria-label={"Preview #{lecture.title}"}
                          >
                            <.icon name="hero-play-circle" class="h-4 w-4" />
                          </.link>
                          <span class="min-w-0">
                            <span class="block truncate font-semibold text-ink">{lecture.title}</span>
                            <span class="block text-xs text-muted">
                              {Catalog.lecture_resource_count(lecture)} resources · {Map.get(
                                @lecture_quiz_question_counts,
                                lecture.id,
                                0
                              )} quiz questions
                            </span>
                          </span>
                        </span>
                        <span class="flex shrink-0 items-center gap-2">
                          <span class="text-sm font-medium text-muted">
                            {minutes(lecture.duration_seconds)} min
                          </span>
                          <button
                            :if={Map.get(@lecture_quiz_question_counts, lecture.id, 0) > 0}
                            type="button"
                            phx-click={
                              JS.push("open_quiz", value: %{id: lecture.id, tab: "questions"})
                            }
                            class="inline-flex items-center gap-1.5 rounded-full border border-black/10 px-4 py-2 text-xs font-semibold text-body transition hover:border-primary hover:text-primary"
                          >
                            <.icon name="hero-eye-mini" class="h-3.5 w-3.5" /> View questions
                          </button>
                          <button
                            type="button"
                            phx-click={
                              JS.push("open_quiz", value: %{id: lecture.id, tab: "generate"})
                            }
                            class="inline-flex items-center gap-1.5 rounded-full bg-ink px-4 py-2 text-xs font-semibold text-white transition hover:bg-primary"
                          >
                            <.icon name="hero-plus-mini" class="h-3.5 w-3.5" /> Add quiz
                          </button>
                          <button
                            type="button"
                            phx-click={JS.push("edit_lecture", value: %{id: lecture.id})}
                            class="grid h-8 w-8 place-items-center rounded-full border border-black/10 text-muted transition hover:border-primary hover:text-primary"
                            title="Edit lecture"
                          >
                            <.icon name="hero-pencil-square" class="h-4 w-4" />
                          </button>
                          <button
                            type="button"
                            phx-click={JS.push("confirm_delete_lecture", value: %{id: lecture.id})}
                            class="grid h-8 w-8 place-items-center rounded-full border border-black/10 text-muted transition hover:border-red-400 hover:text-red-500"
                            title="Delete lecture"
                          >
                            <.icon name="hero-trash" class="h-4 w-4" />
                          </button>
                        </span>
                      </li>
                      <li :if={module.lectures == []} class="px-1 text-sm text-muted">
                        No lectures yet.
                      </li>
                    </ul>

                    <div
                      :for={quiz <- List.wrap(Map.get(@quizzes_by_module, module.id))}
                      class="mt-2.5 flex items-center justify-between gap-3 rounded-lg border border-primary/10 bg-mint/35 px-4 py-3"
                    >
                      <span class="flex min-w-0 items-center gap-3 text-sm text-ink">
                        <.icon
                          name="hero-clipboard-document-check"
                          class="h-5 w-5 shrink-0 text-primary"
                        />
                        <span class="truncate font-semibold">{quiz.title}</span>
                        <span class="shrink-0 text-xs text-muted">
                          {Map.get(@published_question_counts, module.id, 0)} published<span :if={
                            Map.get(@draft_question_counts, module.id, 0) > 0
                          }>
                            · {Map.get(@draft_question_counts, module.id)} to review
                          </span>
                        </span>
                      </span>
                      <span class="flex shrink-0 items-center gap-1.5">
                        <.link
                          navigate={~p"/admin/courses/#{@course.slug}/quizzes/#{quiz.id}/edit"}
                          class="grid h-8 w-8 place-items-center rounded-full text-muted transition hover:bg-white hover:text-primary"
                          title="Manage quiz"
                        >
                          <.icon name="hero-pencil-square" class="h-4 w-4" />
                        </.link>
                        <button
                          type="button"
                          phx-click={JS.push("confirm_delete_quiz", value: %{id: quiz.id})}
                          class="grid h-8 w-8 place-items-center rounded-full text-muted transition hover:bg-white hover:text-red-500"
                          title="Delete quiz"
                        >
                          <.icon name="hero-trash" class="h-4 w-4" />
                        </button>
                      </span>
                    </div>

                    <div class="mt-4 flex flex-wrap items-center gap-4">
                      <button
                        type="button"
                        phx-click={JS.push("new_lecture", value: %{"module-id" => module.id})}
                        class="inline-flex items-center gap-1.5 text-sm font-semibold text-primary transition hover:text-ink"
                      >
                        <.icon name="hero-plus-circle" class="h-4 w-4" /> Add lecture
                      </button>
                      <span
                        :if={
                          is_nil(Map.get(@quizzes_by_module, module.id)) and
                            not module_ready_for_quiz_generation?(
                              module,
                              @lecture_quiz_question_counts
                            )
                        }
                        class="inline-flex cursor-not-allowed items-center gap-1.5 text-sm font-medium text-muted"
                        title="Every lecture in this module needs its own generated lecture quiz first"
                      >
                        Add module quiz
                      </span>
                      <button
                        :if={
                          is_nil(Map.get(@quizzes_by_module, module.id)) and
                            module_ready_for_quiz_generation?(module, @lecture_quiz_question_counts)
                        }
                        type="button"
                        phx-click={JS.push("generate_quiz", value: %{"module-id" => module.id})}
                        class="inline-flex items-center gap-1.5 text-sm font-semibold text-body transition hover:text-primary"
                      >
                        Add module quiz
                      </button>
                    </div>
                    <p
                      :if={
                        is_nil(Map.get(@quizzes_by_module, module.id)) and
                          not module_ready_for_quiz_generation?(
                            module,
                            @lecture_quiz_question_counts
                          )
                      }
                      class="mt-1.5 text-xs text-muted"
                    >
                      Generate a quiz for every lecture in this module before generating the module quiz.
                    </p>
                  </div>
                </div>
              </div>
            </article>
          </div>

          <div
            :if={@course.modules == []}
            class="mt-6 rounded-2xl border border-dashed border-black/10 bg-surface/40 p-10 text-center"
          >
            <span class="mx-auto grid h-12 w-12 place-items-center rounded-full bg-mint text-primary">
              <.icon name="hero-rectangle-stack" class="h-6 w-6" />
            </span>
            <p class="mt-4 font-medium text-ink">No modules yet</p>
            <p class="mt-1 text-sm text-body">
              Add your first module to start building the curriculum.
            </p>
          </div>
        </section>

        <%!-- Enrolled students --%>
        <section
          :if={@active_tab == :students}
          id="students-panel"
          role="tabpanel"
          aria-labelledby="students-tab"
          class="rounded-3xl border border-black/5 bg-white p-6 shadow-card lg:p-8"
        >
          <div class="flex flex-wrap items-start justify-between gap-4">
            <div>
              <h2 class="text-xl font-semibold text-ink">Course access</h2>
              <p class="mt-1 text-sm text-body">
                Grant learners direct access to this course and track current enrollment.
              </p>
            </div>
            <button
              type="button"
              phx-click="open_grant_access"
              disabled={not Catalog.grant_access_allowed?(@course) || @grantable_learners == []}
              title={
                cond do
                  not Catalog.grant_access_allowed?(@course) ->
                    "Publish this course or mark it internal before granting access."

                  @grantable_learners == [] ->
                    "Every learner already has access to this course."

                  true ->
                    "Grant course access"
                end
              }
              class="group inline-flex shrink-0 items-center gap-2 rounded-full bg-ink py-1.5 pl-5 pr-1.5 text-sm font-medium text-white transition hover:bg-primary disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-ink"
            >
              Grant access
              <span class="grid h-8 w-8 place-items-center rounded-full bg-primary text-white transition group-hover:bg-ink">
                <.icon name="hero-key" class="h-4 w-4" />
              </span>
            </button>
          </div>

          <div :if={@students != []} class="mt-5 overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead class="border-b border-black/5 bg-surface text-xs uppercase tracking-wide text-body">
                <tr>
                  <th class="py-3 pr-4 font-semibold">Student</th>
                  <th class="py-3 pr-4 font-semibold">Enrolled</th>
                  <th class="py-3 pr-4 font-semibold">Progress</th>
                  <th class="py-3 pr-4 font-semibold">Quiz scores</th>
                  <th class="py-3 text-right font-semibold">Paid</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-black/5">
                <tr :for={row <- @students} class="transition even:bg-surface/50 hover:bg-mint/45">
                  <td class="py-3 pr-4">
                    <.link
                      navigate={~p"/admin/students/#{row.enrollment.user_id}"}
                      class="font-medium text-ink hover:text-primary"
                    >
                      {row.enrollment.user.name || "Learner"}
                    </.link>
                    <p class="text-xs text-muted">{row.enrollment.user.email}</p>
                  </td>
                  <td class="py-3 pr-4 text-body">{format_date(row.enrollment.activated_at)}</td>
                  <td class="py-3 pr-4">
                    <div class="flex items-center gap-2">
                      <div class="h-1.5 w-16 overflow-hidden rounded-full bg-surface">
                        <div
                          class="h-full rounded-full bg-primary"
                          style={"width: #{row.completion_percent}%"}
                        />
                      </div>
                      <span class="text-xs tabular-nums text-body">{row.completion_percent}%</span>
                    </div>
                  </td>
                  <td class="py-3 pr-4">
                    <p :if={row.quiz_scores == []} class="text-xs text-muted">—</p>
                    <p
                      :for={score <- row.quiz_scores}
                      class={[
                        "text-xs",
                        score.passed && "text-primary",
                        !score.passed && "text-red-600"
                      ]}
                    >
                      {score.quiz_title}: {score.score_percent}%
                    </p>
                  </td>
                  <td class="py-3 text-right font-semibold text-ink">
                    {if row.payment, do: Payments.format_amount(row.payment), else: "—"}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <p :if={@students == []} class="mt-5 rounded-2xl bg-surface p-5 text-body">
            No learners have access to this course yet. Add a learner manually or share the public
            course page.
          </p>

          <div class="mt-10 border-t border-black/5 pt-8">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 class="text-xl font-semibold text-ink">Course reviews</h2>
                <p :if={@review_summary.count > 0} class="mt-0.5 text-sm text-body">
                  <span class="font-semibold text-ink">{@review_summary.average}</span>
                  / 5 · {@review_summary.count} {if @review_summary.count == 1,
                    do: "review",
                    else: "reviews"}
                </p>
              </div>

              <div :if={@reviews != []} class="flex items-center gap-2">
                <button
                  type="button"
                  id="reviews-prev-btn"
                  class="grid h-9 w-9 place-items-center rounded-full border border-black/10 text-ink transition hover:border-primary hover:text-primary disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:border-black/10 disabled:hover:text-ink"
                  aria-label="Previous reviews"
                  disabled
                >
                  <.icon name="hero-chevron-left" class="h-4 w-4" />
                </button>
                <button
                  type="button"
                  id="reviews-next-btn"
                  class="grid h-9 w-9 place-items-center rounded-full border border-black/10 text-ink transition hover:border-primary hover:text-primary disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:border-black/10 disabled:hover:text-ink"
                  aria-label="Next reviews"
                >
                  <.icon name="hero-chevron-right" class="h-4 w-4" />
                </button>
              </div>
            </div>

            <div
              :if={@reviews != []}
              id="course-reviews-scroll"
              phx-hook="ReviewCarousel"
              class="no-scrollbar mt-5 flex gap-4 overflow-x-auto scroll-smooth snap-x snap-mandatory pb-3"
            >
              <article
                :for={review <- @reviews}
                class="snap-start shrink-0 w-[300px] sm:w-[360px] md:w-[400px] flex flex-col justify-between rounded-2xl border border-black/5 bg-surface p-5 transition hover:border-black/10"
              >
                <div>
                  <div class="flex flex-wrap items-center justify-between gap-2">
                    <div class="flex items-center gap-2">
                      <span class="flex gap-0.5">
                        <.icon
                          :for={n <- 1..5}
                          name="hero-star-solid"
                          class={"h-4 w-4 #{if review.rating >= n, do: "text-amber-400", else: "text-black/15"}"}
                        />
                      </span>
                      <span class="text-sm font-semibold text-ink">
                        {review.user.name || review.user.email}
                      </span>
                    </div>
                    <span class="text-xs text-muted">{format_date(review.inserted_at)}</span>
                  </div>
                  <p
                    :if={review.body}
                    class="mt-3 whitespace-pre-line text-sm text-body leading-relaxed"
                  >
                    {review.body}
                  </p>
                  <p
                    :if={is_nil(review.body) || review.body == ""}
                    class="mt-3 text-xs italic text-muted"
                  >
                    No written comment provided.
                  </p>
                </div>
              </article>
            </div>

            <p :if={@reviews == []} class="mt-5 rounded-2xl bg-surface p-5 text-body">
              No reviews yet. Learners are asked to rate the course when they finish the
              final lecture.
            </p>
          </div>
        </section>

        <%!-- Analytics --%>
        <section
          :if={@active_tab == :analytics}
          id="analytics-panel"
          role="tabpanel"
          aria-labelledby="analytics-tab"
          class="space-y-6"
        >
          <div class="analytics-card flex flex-wrap items-center justify-between gap-6 px-6 py-7 lg:px-8">
            <div>
              <div class="flex items-center gap-2">
                <span class="text-xs font-bold uppercase tracking-wider text-primary">
                  Course Intelligence
                </span>
              </div>
              <h2 class="mt-1 text-2xl font-bold text-ink sm:text-3xl">Course analytics</h2>
              <p class="mt-1 text-sm text-body">
                Learning progress, quiz performance, conversion, and video drop-off for {@course.title}.
              </p>
            </div>
            <.link
              navigate={~p"/admin/analytics?#{%{course_id: @course.id}}"}
              class="inline-flex items-center gap-2 rounded-full border border-ink px-5 py-2.5 text-sm font-medium text-ink transition hover:bg-ink hover:text-white"
            >
              <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
              Open in full Analytics explorer
            </.link>
          </div>

          <%!-- Summary KPIs --%>
          <div class="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
            <.stat_card
              label="Completion rate"
              value={percent_or_dash(@analytics_completion_rate)}
              icon="hero-rectangle-stack"
              hint="Average across all modules"
            />
            <.stat_card
              label="Average quiz score"
              value={percent_or_dash(@analytics_avg_quiz_score)}
              icon="hero-clipboard-document-check"
              hint="Across module quizzes"
            />
            <.stat_card
              label="Quiz pass rate"
              value={percent_or_dash(@analytics_quiz_pass_rate)}
              icon="hero-academic-cap"
              hint="Passed vs submitted"
            />
            <.stat_card
              label="Active learners"
              value={@student_count}
              icon="hero-users"
              hint="Currently enrolled"
            />
          </div>

          <%!-- Journey / Conversion Funnel --%>
          <div class="analytics-card overflow-hidden">
            <div class="flex flex-wrap items-baseline justify-between gap-3 border-b border-neutral-700 px-6 py-7 lg:px-8">
              <div>
                <p class="text-xs font-bold uppercase tracking-wider text-primary">Journey</p>
                <h3 class="mt-2 text-2xl font-semibold text-ink">Conversion funnel</h3>
              </div>
              <p :if={@analytics_funnel_conversion} class="text-sm text-body">
                <span class="font-semibold text-primary">{@analytics_funnel_conversion}%</span>
                overall conversion
              </p>
            </div>
            <div class="flex flex-wrap items-stretch gap-3 px-6 py-7 lg:px-8">
              <div :for={step <- @analytics_funnel} class="contents">
                <div class="min-w-[130px] flex-1 rounded-2xl border border-black/5 bg-white p-4 text-center shadow-sm">
                  <p class="text-xs font-semibold uppercase tracking-wide text-body">{step.step}</p>
                  <p class="mt-2 text-2xl font-bold text-ink sm:text-3xl">{step.count}</p>
                  <p class="mt-1 text-xs font-medium text-body">
                    {if step.percent_of_previous,
                      do: "#{step.percent_of_previous}% of prev",
                      else: raw("&nbsp;")}
                  </p>
                </div>
                <.icon
                  :if={!step.last?}
                  name="hero-chevron-right"
                  class="h-5 w-5 shrink-0 self-center text-body"
                />
              </div>
            </div>
          </div>

          <%!-- 2-column: Module Performance & Learner Retention --%>
          <div class="grid gap-6 lg:grid-cols-2">
            <%!-- Learning performance by module --%>
            <div class="analytics-card overflow-hidden">
              <div class="border-b border-neutral-700 px-6 py-7 lg:px-8">
                <p class="text-xs font-bold uppercase tracking-wider text-primary">Performance</p>
                <h3 class="mt-2 text-2xl font-semibold text-ink">Completion & Quiz score</h3>
                <p class="mt-1 text-sm text-body">Module completion vs average quiz result</p>
              </div>

              <div :if={@analytics_module_rows != []} class="px-6 pb-6 pt-5 lg:px-8">
                <div class="mb-5 flex justify-end gap-6 text-xs font-semibold text-body">
                  <span class="flex items-center gap-1.5">
                    <span class="h-3 w-3 rounded bg-ink" /> Completion
                  </span>
                  <span class="flex items-center gap-1.5">
                    <span class="h-3 w-3 rounded bg-primary" /> Quiz score
                  </span>
                </div>

                <div class="divide-y divide-black/5">
                  <div
                    :for={row <- @analytics_module_rows}
                    class="grid items-center gap-4 py-4 sm:grid-cols-[180px_1fr]"
                  >
                    <p class="text-sm font-medium text-ink truncate" title={row.title}>{row.title}</p>
                    <div class="space-y-2">
                      <.percent_bar
                        label="Completion"
                        percent={row.completion_percent}
                        color="bg-ink"
                      />
                      <.percent_bar
                        label="Quiz score"
                        percent={row.quiz_score_percent || 0}
                        color="bg-primary"
                      />
                    </div>
                  </div>
                </div>
              </div>

              <p
                :if={@analytics_module_rows == []}
                class="mx-6 my-6 rounded-xl border border-black/5 bg-surface/70 p-6 text-center text-sm text-body"
              >
                No modules yet for this course.
              </p>
            </div>

            <%!-- Learner retention --%>
            <div class="analytics-card overflow-hidden">
              <div class="border-b border-neutral-700 px-6 py-7 lg:px-8">
                <p class="text-xs font-bold uppercase tracking-wider text-primary">Drop-off</p>
                <h3 class="mt-2 text-2xl font-semibold text-ink">Learner retention</h3>
                <p class="mt-1 text-sm text-body">Active learners completing each module milestone</p>
              </div>

              <div
                :if={@analytics_module_rows != []}
                class="divide-y divide-black/5 px-6 py-6 lg:px-8"
              >
                <div
                  :for={{row, index} <- Enum.with_index(@analytics_module_rows, 1)}
                  class="flex items-start gap-4 py-4 first:pt-0 last:pb-0"
                >
                  <span class="mt-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-full border border-primary text-xs font-bold text-primary">
                    {String.pad_leading(Integer.to_string(index), 2, "0")}
                  </span>
                  <div class="min-w-0 flex-1">
                    <div class="flex items-center justify-between gap-3">
                      <p class="text-sm font-semibold text-ink truncate">{row.title}</p>
                      <span class="text-xs font-bold text-primary">{row.completion_percent}%</span>
                    </div>
                    <div class="mt-2 h-2.5 overflow-hidden rounded-full bg-neutral-100">
                      <div
                        class="h-full rounded-full bg-primary"
                        style={"width: #{row.completion_percent}%"}
                      />
                    </div>
                    <p class="mt-1 text-xs text-muted">
                      {row.remaining_learners} learners completed
                    </p>
                  </div>
                </div>
              </div>

              <p
                :if={@analytics_module_rows == []}
                class="mx-6 my-6 rounded-xl border border-black/5 bg-surface/70 p-6 text-center text-sm text-body"
              >
                No module retention data yet.
              </p>
            </div>
          </div>

          <%!-- Video Drop-off & Lecture Engagement --%>
          <div class="analytics-card overflow-hidden">
            <div class="border-b border-neutral-700 px-6 py-7 lg:px-8">
              <p class="text-xs font-bold uppercase tracking-wider text-primary">Engagement</p>
              <h3 class="mt-2 text-2xl font-semibold text-ink">Video watch drop-off</h3>
              <p class="mt-1 text-sm text-body">
                Earliest drop-off points among learners in progress
              </p>
            </div>

            <div
              :if={@analytics_video_dropoffs != []}
              class="divide-y divide-black/5 px-6 py-6 lg:px-8"
            >
              <div
                :for={row <- @analytics_video_dropoffs}
                class="grid items-center gap-4 py-4 first:pt-0 last:pb-0 sm:grid-cols-[200px_1fr_100px]"
              >
                <div>
                  <p class="text-sm font-semibold text-ink truncate" title={row.title}>{row.title}</p>
                  <p class="text-xs text-muted">
                    {row.viewers} {ngettext("viewer", "viewers", row.viewers)} in progress
                  </p>
                </div>
                <div class="space-y-1">
                  <div class="h-2.5 overflow-hidden rounded-full bg-neutral-100">
                    <div
                      class="h-full rounded-full bg-primary"
                      style={"width: #{row.dropoff_percent}%"}
                    />
                  </div>
                  <div class="flex justify-between text-xs text-muted">
                    <span>Avg stop: {round(row.avg_position_seconds)}s</span>
                    <span>Total: {row.duration_seconds || 0}s</span>
                  </div>
                </div>
                <span class="text-right text-sm font-bold text-ink">{row.dropoff_percent}%</span>
              </div>
            </div>

            <p
              :if={@analytics_video_dropoffs == []}
              class="mx-6 my-6 rounded-xl border border-black/5 bg-surface/70 p-6 text-center text-sm text-body"
            >
              No in-progress video drop-offs recorded. Learners are completing lectures or haven't begun playback yet.
            </p>
          </div>

          <%!-- Monthly Revenue Chart (for paid courses) --%>
          <div :if={!@course.is_free} class="analytics-card overflow-hidden">
            <div class="border-b border-neutral-700 px-6 py-7 lg:px-8">
              <p class="text-xs font-bold uppercase tracking-wider text-primary">Financials</p>
              <h3 class="mt-2 text-2xl font-semibold text-ink">Monthly course revenue</h3>
              <p class="mt-1 text-sm text-body">Historical payment earnings for {@course.title}</p>
            </div>
            <div class="p-6 lg:p-8">
              <.column_chart
                title="Revenue by month"
                data={@analytics_revenue_chart}
                empty_message="No successful payments recorded for this course."
              />
            </div>
          </div>
        </section>

        <%!-- Course modal --%>
        <.modal :if={@modal == :course} id="course-modal" show on_cancel={JS.push("close_modal")}>
          <.live_component
            module={CourseLive.FormComponent}
            id={@course.id}
            title={@form_title}
            action={:edit}
            course={@course}
            patch={fn course -> ~p"/admin/courses/#{course.slug}" end}
          />
        </.modal>

        <%!-- Module modal --%>
        <.modal
          :if={@modal == :module}
          id="module-modal"
          show
          dismissable={false}
          on_cancel={JS.push("close_modal")}
        >
          <.live_component
            module={CourseModuleLive.FormComponent}
            id={@course_module.id || :new_module}
            title={@form_title}
            action={if @course_module.id, do: :edit, else: :new}
            course_module={@course_module}
            patch={~p"/admin/courses/#{@course.slug}"}
          />
        </.modal>

        <%!-- Lecture modal --%>
        <.modal
          :if={@modal == :lecture}
          id="lecture-modal"
          show
          dismissable={false}
          max_width="max-w-4xl"
          on_cancel={JS.push("close_modal")}
        >
          <.live_component
            module={LectureLive.FormComponent}
            id={@lecture.id || :new_lecture}
            title={@form_title}
            action={if @lecture.id, do: :edit, else: :new}
            lecture={@lecture}
            current_user={@current_user}
            course_slug={@course.slug}
            patch={~p"/admin/courses/#{@course.slug}"}
          />
        </.modal>

        <%!-- Lecture quiz modal --%>
        <.modal
          :if={@modal == :quiz}
          id="quiz-modal"
          show
          dismissable={false}
          max_width="max-w-5xl"
          on_cancel={JS.push("close_modal")}
        >
          {live_render(@socket, WasomiWeb.AdminLive.LectureQuizEdit,
            id: "quiz-live-#{@quiz_lecture_id}-#{@quiz_modal_tab}",
            session: %{
              "course_slug" => @course.slug,
              "lecture_id" => to_string(@quiz_lecture_id),
              "initial_tab" => to_string(@quiz_modal_tab),
              "embedded" => true
            }
          )}
        </.modal>

        <%!-- Course-first access grant modal --%>
        <.modal
          :if={@modal == :grant_access}
          id="grant-access-modal"
          show
          on_cancel={JS.push("close_modal")}
        >
          <.header>
            Grant access to {@course.title}
            <:subtitle>
              Choose one or more learners. Access activates immediately and each learner is notified
              by email and in-app.
            </:subtitle>
          </.header>

          <.simple_form
            for={@grant_access_form}
            id="grant-access-form"
            phx-change="validate_grant_access"
            phx-submit="grant_access"
          >
            <div>
              <p class="text-sm font-medium text-ink">Course</p>
              <p class="mt-1 rounded-xl bg-surface px-3 py-2.5 text-sm text-body">
                {@course.title}
              </p>
            </div>

            <div>
              <div class="mb-2 flex items-center justify-between gap-3">
                <p class="text-sm font-semibold text-ink">Learners</p>
                <p class="text-xs font-semibold uppercase text-muted">
                  {length(@selected_grant_learner_ids)} selected
                </p>
              </div>

              <div
                id="grant-access-learners-combobox"
                phx-hook="SearchableMultiSelect"
                class="relative"
              >
                <button
                  type="button"
                  data-role="trigger"
                  class="flex w-full items-center justify-between rounded-lg border border-black/15 bg-white px-4 py-3 text-left text-sm text-ink transition focus:border-primary focus:outline-none focus:ring-4 focus:ring-primary/10"
                >
                  <span>
                    <span :if={@selected_grant_learner_ids == []} class="text-muted">
                      Select learners
                    </span>
                    <span :if={@selected_grant_learner_ids != []} class="block truncate">
                      {selected_learner_label(@grantable_learners, @selected_grant_learner_ids)}
                    </span>
                  </span>
                  <.icon name="hero-chevron-up-down" class="h-4 w-4 shrink-0 text-muted" />
                </button>

                <div
                  data-role="panel"
                  class="absolute z-20 mt-1 hidden w-full overflow-hidden rounded-2xl border border-black/10 bg-white shadow-lg"
                >
                  <div class="p-2">
                    <input
                      type="text"
                      data-role="search"
                      placeholder="Search learners..."
                      autocomplete="off"
                      class="block w-full rounded-lg border border-black/10 px-3 py-2 text-sm text-ink focus:border-primary focus:outline-none focus:ring-4 focus:ring-primary/10"
                    />
                  </div>

                  <div class="max-h-64 overflow-y-auto px-1 pb-2">
                    <label
                      :for={learner <- @grantable_learners}
                      data-role="option"
                      class={[
                        "flex cursor-pointer items-center gap-3 rounded-lg px-3 py-2.5 transition hover:bg-soft",
                        learner_selected?(learner, @selected_grant_learner_ids) && "bg-mint/40"
                      ]}
                    >
                      <input
                        type="checkbox"
                        name="learner_ids[]"
                        value={learner.id}
                        checked={learner_selected?(learner, @selected_grant_learner_ids)}
                        class="h-4 w-4 rounded border-black/20 text-primary focus:ring-primary/20"
                      />
                      <span class="min-w-0">
                        <span class="block truncate text-sm font-semibold text-ink">
                          {learner.name || "Learner"}
                        </span>
                        <span class="block truncate text-xs text-muted">{learner.email}</span>
                      </span>
                    </label>

                    <p data-role="empty" class="hidden px-3 py-5 text-center text-sm text-muted">
                      No learners match.
                    </p>

                    <div :if={@grantable_learners == []} class="px-3 py-5 text-sm text-body">
                      Every learner already has access to this course.
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <input type="hidden" name="grant_access_form[course_id]" value={@course.id} />

            <.input
              field={@grant_access_form[:reason]}
              type="textarea"
              label="Reason for granting access"
              placeholder="e.g. Manual enrollment for a partner scholarship"
              rows="3"
              required
            />

            <:actions>
              <.button phx-disable-with="Granting access...">
                {grant_access_button_label(@selected_grant_learner_ids)}
              </.button>
            </:actions>
          </.simple_form>
        </.modal>

        <%!-- Publish readiness checklist --%>
        <.modal
          :if={@publish_checklist}
          id="publish-checklist-modal"
          show
          on_cancel={JS.push("close_publish_checklist")}
        >
          <h2 class="text-xl font-semibold text-ink">
            "{@course.title}" isn't ready to publish yet
          </h2>
          <p class="mt-1 text-sm text-body">
            Complete the items below before making this course public.
          </p>
          <.publish_checklist stages={@publish_checklist} />
          <div class="mt-7 flex flex-col gap-3 sm:flex-row sm:items-center">
            <button
              type="button"
              phx-click={JS.push("close_publish_checklist") |> JS.push("edit_course")}
              class="inline-flex items-center justify-center rounded-full bg-ink px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-primary"
            >
              Edit course
            </button>
            <button
              type="button"
              phx-click="close_publish_checklist"
              class="inline-flex items-center justify-center rounded-full border border-black/10 px-5 py-2.5 text-sm font-semibold text-ink transition hover:border-primary hover:text-primary"
            >
              Close
            </button>
          </div>
        </.modal>

        <%!-- Unpublish confirmation --%>
        <.confirm_modal
          :if={@confirming_unpublish?}
          id="unpublish-course-modal"
          title={"Unpublish \"#{@course.title}\"?"}
          confirm_label="Unpublish"
          confirm={JS.push("unpublish_course")}
          cancel={JS.push("cancel_unpublish_course")}
        >
          It goes back to draft and leaves the public catalog. Enrolled learners keep their access, and you can publish it again at any time.
        </.confirm_modal>

        <%!-- Delete quiz confirmation --%>
        <.confirm_modal
          :if={@deleting_quiz}
          id="delete-quiz-modal"
          title={"Delete \"#{@deleting_quiz.title}\"?"}
          confirm_label="Delete quiz"
          confirm={JS.push("delete_quiz", value: %{id: @deleting_quiz.id})}
          cancel={JS.push("cancel_delete_quiz")}
        >
          This can't be undone. All of its questions and options will be permanently removed.
        </.confirm_modal>

        <%!-- Delete module confirmation --%>
        <.confirm_modal
          :if={@deleting_module}
          id="delete-module-modal"
          title={"Delete \"#{@deleting_module.title}\" and all its lectures?"}
          confirm_label="Delete module"
          confirm={JS.push("delete_module", value: %{id: @deleting_module.id})}
          cancel={JS.push("cancel_delete_module")}
        >
          This can't be undone. All of its lectures will be permanently removed.
        </.confirm_modal>

        <%!-- Delete lecture confirmation --%>
        <.confirm_modal
          :if={@deleting_lecture}
          id="delete-lecture-modal"
          title={"Delete lecture \"#{@deleting_lecture.title}\"?"}
          confirm_label="Delete lecture"
          confirm={JS.push("delete_lecture", value: %{id: @deleting_lecture.id})}
          cancel={JS.push("cancel_delete_lecture")}
        >
          This can't be undone.
        </.confirm_modal>
      </div>
    </.admin_layout>
    """
  end

  defp format_channel_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y")
  defp format_channel_time(_), do: "—"

  defp course_detail_tab("analytics", _current_tab), do: :analytics
  defp course_detail_tab("students", _current_tab), do: :students
  defp course_detail_tab("curriculum", _current_tab), do: :curriculum
  defp course_detail_tab(_tab, current_tab), do: current_tab

  defp percent_or_dash(nil), do: "—"
  defp percent_or_dash(value), do: "#{value}%"

  defp percent(_count, 0), do: 0
  defp percent(count, total), do: round(count / total * 100)

  defp compact_revenue_label(amount_minor) do
    major = amount_minor / 100

    cond do
      major >= 1_000_000 -> compact_number(major / 1_000_000) <> "M KES"
      major >= 10_000 -> compact_number(major / 1_000) <> "K KES"
      true -> Payments.format_minor(amount_minor)
    end
  end

  defp compact_number(number) do
    rounded = Float.round(number, 1)

    if rounded == trunc(rounded) do
      Integer.to_string(trunc(rounded))
    else
      :erlang.float_to_binary(rounded, decimals: 1)
    end
  end

  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) when is_binary(value), do: String.to_integer(value)

  defp minutes(seconds) when is_integer(seconds), do: max(1, div(seconds + 59, 60))
  defp minutes(_), do: 0

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")
  defp format_date(_), do: "—"
end
