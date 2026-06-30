defmodule WasomiWeb.DashboardLive do
  use WasomiWeb, :live_view

  alias Wasomi.{Certificates, Enrollments, Learning, Payments}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Learning.subscribe(socket.assigns.current_user)
      Payments.subscribe(socket.assigns.current_user)
    end

    {:ok,
     socket
     |> assign(:page_title, "My learning")
     |> refresh_dashboard()}
  end

  @impl true
  def handle_info({event, _subject}, socket)
      when event in [
             :lecture_completed,
             :module_completed,
             :course_completed,
             :certificate_ready,
             :payment_confirmed
           ] do
    {:noreply, refresh_dashboard(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.student_layout active={:dashboard} current_user={@current_user}>
      <section class="bg-gradient-to-b from-mint via-white to-soft py-12 lg:py-16">
        <div class="mx-auto max-w-container px-5 lg:px-10">
          <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
            Learner dashboard
          </span>
          <h1 class="mt-5 text-4xl font-semibold leading-[1.1] text-dark sm:text-5xl">
            Welcome back, {first_name(@current_user.name)}.
          </h1>
          <p class="mt-4 max-w-2xl text-lg text-body">
            Continue learning, track your progress, and keep your achievements in one place.
          </p>

          <div class="mt-8 grid gap-4 sm:grid-cols-3">
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
        <div class="mx-auto max-w-container space-y-12 px-5 lg:px-10">
          <div>
            <div class="flex flex-wrap items-end justify-between gap-4">
              <div>
                <p class="text-sm font-semibold uppercase tracking-wider text-primary">
                  Continue learning
                </p>
                <h2 class="mt-2 text-3xl font-semibold text-dark">Pick up where you left off.</h2>
              </div>
              <.link
                :if={@course_cards != []}
                navigate={~p"/courses-taken"}
                class="text-sm font-medium text-primary transition hover:text-dark"
              >
                View all courses →
              </.link>
            </div>

            <div
              :if={@resume_cards != []}
              id="dashboard-courses"
              class="mt-7 grid gap-7 sm:grid-cols-2"
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
              class="mt-7 rounded-3xl border border-black/5 bg-white p-8 text-center sm:p-12"
            >
              <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
                <.icon name="hero-academic-cap" class="h-7 w-7" />
              </span>
              <h3 class="mt-5 text-xl font-semibold text-dark">Your learning shelf is ready.</h3>
              <p class="mx-auto mt-2 max-w-lg text-body">
                Enroll in a course and it will appear here as soon as payment is confirmed.
              </p>
              <.link
                navigate={~p"/courses"}
                class="mt-6 inline-flex rounded-full bg-dark px-6 py-3 font-medium text-white transition hover:bg-primary"
              >
                Browse courses
              </.link>
            </div>
          </div>

          <section
            id="dashboard-receipts"
            class="rounded-3xl border border-black/5 bg-white p-6 sm:p-8"
          >
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="text-sm font-semibold uppercase tracking-wider text-primary">Billing</p>
                <h2 class="mt-2 text-2xl font-semibold text-dark">Payment receipts</h2>
              </div>
              <span class="grid h-11 w-11 place-items-center rounded-full bg-mint text-primary">
                <.icon name="hero-receipt-percent" class="h-6 w-6" />
              </span>
            </div>

            <div :if={@receipts != []} class="mt-6 divide-y divide-black/5">
              <article
                :for={receipt <- @receipts}
                id={"payment-receipt-#{receipt.id}"}
                class="py-4 first:pt-0 last:pb-0"
              >
                <div class="flex items-start justify-between gap-4">
                  <div class="min-w-0">
                    <h3 class="truncate font-medium text-dark">{receipt.course.title}</h3>
                    <p class="mt-1 text-sm text-muted">
                      Paid {format_date(receipt.paid_at)} via {provider_name(receipt.provider)}
                    </p>
                  </div>
                  <p class="shrink-0 font-semibold text-dark">
                    {Payments.format_amount(receipt)}
                  </p>
                </div>
                <div class="mt-3 flex items-center justify-between gap-4 rounded-2xl bg-soft px-4 py-3 text-xs">
                  <span class="text-muted">Receipt reference</span>
                  <span class="break-all text-right font-medium text-dark">
                    {receipt.provider_reference}
                  </span>
                </div>
              </article>
            </div>

            <p :if={@receipts == []} class="mt-6 rounded-2xl bg-soft p-5 text-body">
              Successful course payments will appear here.
            </p>
          </section>
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
    <div class="flex items-center gap-4 rounded-3xl border border-black/5 bg-white p-5">
      <span class="grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-mint text-primary">
        <.icon name={@icon} class="h-6 w-6" />
      </span>
      <div>
        <p class="text-2xl font-semibold text-dark">{@value}</p>
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

    socket
    |> assign(:course_cards, course_cards)
    |> assign(:resume_cards, resume_cards(course_cards))
    |> assign(:completed_count, completed_count)
    |> assign(:certificates, Certificates.list_for_user(user))
    |> assign(:receipts, Payments.list_receipts_for_user(user))
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

  defp resume_lecture(course, progress) do
    lectures = Enum.flat_map(course.modules, & &1.lectures)

    Enum.find(lectures, fn lecture ->
      case progress[lecture.id] do
        %{status: :completed} -> false
        _progress -> true
      end
    end) || List.last(lectures)
  end

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%B %-d, %Y")
  defp format_date(_datetime), do: "date unavailable"

  defp provider_name(:paystack), do: "Paystack"
  defp provider_name(:mpesa), do: "M-Pesa"
  defp provider_name(provider), do: provider |> to_string() |> String.capitalize()
end
