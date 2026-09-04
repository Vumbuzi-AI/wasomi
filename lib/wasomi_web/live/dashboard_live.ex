defmodule WasomiWeb.DashboardLive do
  use WasomiWeb, :live_view

  alias Wasomi.{Accounts, Catalog, Certificates, Enrollments, Learning, Notifications, Payments}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Learning.subscribe(socket.assigns.current_user)
      Notifications.subscribe(socket.assigns.current_user)
    end

    {:ok,
     socket
     |> assign(:page_title, "My learning")
     |> refresh_dashboard()}
  end

  @impl true
  def handle_event("tour_completed", _params, socket) do
    {:ok, user} = Accounts.complete_user_tour(socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:current_user, user)
     |> assign(:tour_completed?, true)}
  end

  @impl true
  def handle_info({event, _subject}, socket)
      when event in [
             :lecture_completed,
             :module_completed,
             :course_completed,
             :certificate_ready,
             :payment_confirmed,
             :enrollment_granted,
             :notification_created
           ] do
    {:noreply, refresh_dashboard(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.student_layout active={:dashboard} current_user={@current_user}>
      <section class="bg-surface py-12 lg:py-16">
        <div class="w-full px-5 lg:px-8">
          <h1 class="text-4xl font-semibold leading-[1.1] text-ink sm:text-5xl">
            {@welcome_state.title}
          </h1>
          <p class="mt-4 max-w-2xl text-lg text-body">
            {@welcome_state.body}
          </p>
          <.link
            :if={@welcome_state.action}
            navigate={@welcome_state.action.path}
            class="mt-6 inline-flex rounded-full bg-ink px-6 py-3 font-medium text-white transition hover:bg-primary"
          >
            {@welcome_state.action.label}
          </.link>

          <div
            :if={@first_run? and not @tour_completed?}
            class="mt-8 flex flex-wrap items-center justify-between gap-4 rounded-3xl border border-ink/10 bg-white px-5 py-4 shadow-card"
          >
            <div class="flex items-center gap-3">
              <span class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-ink text-white">
                <.icon name="hero-sparkles" class="h-5 w-5" />
              </span>
              <p class="text-sm font-medium text-ink">
                New here? Let us show you around — takes about 30 seconds.
              </p>
            </div>
            <div class="flex shrink-0 items-center gap-2">
              <button
                id="product-tour"
                type="button"
                phx-hook="ProductTour"
                class="rounded-full bg-primary px-5 py-2 text-sm font-semibold text-white transition hover:bg-ink"
              >
                Show me around
              </button>
              <button
                type="button"
                phx-click="tour_completed"
                class="rounded-full px-4 py-2 text-sm font-medium text-body transition hover:text-ink"
              >
                I'll find my way
              </button>
            </div>
          </div>

          <div :if={!@first_run?} id="dashboard-stats" class="mt-8 grid gap-4 sm:grid-cols-3">
            <.learner_stat_card
              label="Courses"
              value={length(@course_cards)}
              icon="hero-academic-cap"
            />
            <.learner_stat_card label="Completed" value={@completed_count} icon="hero-check-badge" />
            <.learner_stat_card label="Certificates" value={length(@certificates)} icon="hero-trophy" />
          </div>
        </div>
      </section>

      <section class="pb-16 lg:pb-24">
        <div class="w-full space-y-5 px-5 lg:px-8">
          <%!-- First-time learner: courses to start from, not empty progress. --%>
          <div :if={@first_run?} id="dashboard-starter">
            <div class="flex flex-wrap items-end justify-between gap-4">
              <h2 class="text-3xl font-semibold text-ink">Choose a course to begin.</h2>
              <.link
                :if={@starter_courses != []}
                navigate={~p"/catalog"}
                class="text-sm font-medium text-primary transition hover:text-ink"
              >
                Browse all courses →
              </.link>
            </div>

            <div :if={@starter_courses != []} class="mt-7 grid gap-7 sm:grid-cols-2 xl:grid-cols-3">
              <WasomiWeb.HomeComponents.course_card :for={course <- @starter_courses} course={course} />
            </div>

            <div :if={@more_courses?} class="mt-8 text-center">
              <.link
                navigate={~p"/catalog"}
                class="inline-flex rounded-full border border-black/10 px-6 py-3 font-medium text-ink transition hover:border-primary hover:text-primary"
              >
                View the full catalog
              </.link>
            </div>

            <p
              :if={@starter_courses == []}
              class="mt-7 rounded-3xl border border-black/5 bg-white p-8 text-body shadow-card"
            >
              New courses are on the way — check back soon.
            </p>
          </div>

          <div :if={!@first_run?}>
            <div class="flex flex-wrap items-end justify-between gap-4">
              <h2 class="text-3xl font-semibold text-ink">Pick up where you left off.</h2>
              <.link
                :if={@course_cards != []}
                navigate={~p"/courses-taken"}
                class="text-sm font-medium text-primary transition hover:text-ink"
              >
                View all courses →
              </.link>
            </div>

            <div
              :if={@resume_cards != []}
              id="dashboard-courses"
              class="mt-7 grid gap-7 sm:grid-cols-2 xl:grid-cols-3"
            >
              <.course_card
                :for={card <- @resume_cards}
                card={card}
                id={"dashboard-course-#{card.course.id}"}
                progress_id={"course-progress-#{card.course.id}"}
              />
            </div>

            <div
              :if={@course_cards == []}
              id="dashboard-empty-courses"
              class="mt-7 rounded-3xl border border-black/5 bg-white p-8 text-center shadow-card sm:p-12"
            >
              <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
                <.icon name="hero-academic-cap" class="h-7 w-7" />
              </span>
              <h3 class="mt-5 text-xl font-semibold text-ink">Your learning shelf is ready.</h3>
              <p class="mx-auto mt-2 max-w-lg text-body">
                Enroll in a course and it will appear here as soon as payment is confirmed.
              </p>
              <.link
                navigate={~p"/catalog"}
                class="mt-6 inline-flex rounded-full bg-ink px-6 py-3 font-medium text-white transition hover:bg-primary"
              >
                Browse courses
              </.link>
            </div>
          </div>
        </div>
      </section>
    </.student_layout>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true

  defp learner_stat_card(assigns) do
    ~H"""
    <div class="flex items-center gap-4 rounded-3xl border border-black/5 bg-white p-5 shadow-card">
      <span class="grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-mint text-primary">
        <.icon name={@icon} class="h-6 w-6" />
      </span>
      <div>
        <p class="text-2xl font-semibold text-ink">{@value}</p>
        <p class="text-sm text-muted">{@label}</p>
      </div>
    </div>
    """
  end

  defp refresh_dashboard(socket) do
    user = socket.assigns.current_user

    course_cards =
      user
      |> Enrollments.list_active_for_user()
      |> Enum.map(fn enrollment ->
        course = enrollment.course
        progress = Learning.course_progress(user, course)

        %{
          enrollment: enrollment,
          course: course,
          progress: progress,
          resume_lecture: resume_lecture(course, progress.progress),
          started?: map_size(progress.progress) > 0
        }
      end)

    completed_count = Enum.count(course_cards, & &1.progress.complete?)
    certificates = Certificates.list_for_user(user)
    receipts = Payments.list_receipts_for_user(user)

    # No enrollments/certificates/receipts: show courses to start, not zeroed metrics.
    first_run? = course_cards == [] and certificates == [] and receipts == []
    published = if first_run?, do: Catalog.list_published_courses(), else: []
    starter_limit = 6

    socket
    |> assign(:course_cards, course_cards)
    |> assign(:resume_cards, resume_cards(course_cards))
    |> assign(:completed_count, completed_count)
    |> assign(:certificates, certificates)
    |> assign(:receipts, receipts)
    |> assign(:first_run?, first_run?)
    |> assign(:starter_courses, Enum.take(published, starter_limit))
    |> assign(:more_courses?, length(published) > starter_limit)
    |> assign(:tour_completed?, Accounts.tour_completed?(user))
    |> assign_welcome_state()
  end

  # Surface up to four courses, prioritising those still in progress.
  defp resume_cards(course_cards) do
    {in_progress, rest} = Enum.split_with(course_cards, &(!&1.progress.complete?))
    Enum.take(in_progress ++ rest, 4)
  end

  defp first_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.split()
    |> List.first()
    |> case do
      nil -> "learner"
      first_name -> first_name
    end
  end

  defp first_name(_name), do: "learner"

  defp assign_welcome_state(socket) do
    assign(socket, :welcome_state, welcome_state(socket.assigns))
  end

  defp welcome_state(%{
         current_user: user,
         course_cards: [],
         certificates: [],
         receipts: []
       }) do
    if profile_started?(user) do
      catalog_welcome_state(user)
    else
      %{
        title: "Welcome to Wasomi, #{first_name(user.name)}.",
        body:
          "Start by completing your learner profile so we can shape better course recommendations for you.",
        action: %{label: "Complete profile", path: ~p"/users/settings"}
      }
    end
  end

  defp welcome_state(%{current_user: user, course_cards: []}), do: catalog_welcome_state(user)

  defp welcome_state(%{current_user: user, course_cards: course_cards}) do
    if Enum.any?(course_cards, & &1.started?) do
      %{
        title: "Welcome back, #{first_name(user.name)}.",
        body: "Continue learning, track your progress, and keep your achievements in one place.",
        action: nil
      }
    else
      %{
        title: "Your first course is ready, #{first_name(user.name)}.",
        body:
          "Start with the first lesson, then come back here any time to pick up where you left off.",
        action: %{label: "Start learning", path: ~p"/courses-taken"}
      }
    end
  end

  defp catalog_welcome_state(user) do
    %{
      title: "Ready when you are, #{first_name(user.name)}.",
      body: "Pick one of the courses below to start building practical skills.",
      action: nil
    }
  end

  defp profile_started?(user) do
    user
    |> Map.take([
      :avatar_key,
      :bio,
      :country,
      :experience_level,
      :headline,
      :industry,
      :learning_goal,
      :occupation,
      :organization
    ])
    |> Map.values()
    |> Enum.any?(&present?/1)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(nil), do: false
  defp present?(_value), do: true

  defp resume_lecture(course, progress) do
    lectures = Enum.flat_map(course.modules, & &1.lectures)

    Enum.find(lectures, fn lecture ->
      case progress[lecture.id] do
        %{status: :completed} -> false
        _progress -> true
      end
    end) || List.last(lectures)
  end
end
