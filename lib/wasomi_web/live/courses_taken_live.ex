defmodule WasomiWeb.CoursesTakenLive do
  use WasomiWeb, :live_view

  alias Wasomi.{Enrollments, Learning}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Learning.subscribe(socket.assigns.current_user)
    end

    {:ok,
     socket
     |> assign(:page_title, "My courses")
     |> load_courses()}
  end

  @impl true
  def handle_info({event, _subject}, socket)
      when event in [:lecture_completed, :module_completed, :course_completed] do
    {:noreply, load_courses(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.student_layout active={:courses} current_user={@current_user}>
      <div class="mx-auto max-w-container px-5 py-10 lg:px-10 lg:py-12">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p class="text-sm font-semibold uppercase tracking-wider text-primary">My courses</p>
            <h1 class="mt-2 text-3xl font-semibold text-dark">Courses you're taking.</h1>
          </div>
          <span :if={@course_cards != []} class="text-sm text-muted">
            {length(@course_cards)} {pluralize(length(@course_cards), "course")}
          </span>
        </div>

        <div
          :if={@course_cards != []}
          id="courses-taken-list"
          class="mt-8 grid gap-7 sm:grid-cols-2 xl:grid-cols-3"
        >
          <.course_card
            :for={card <- @course_cards}
            card={card}
            id={"courses-taken-#{card.course.id}"}
            progress_id={"course-progress-#{card.course.id}"}
          />
        </div>

        <div
          :if={@course_cards == []}
          id="courses-taken-empty"
          class="mt-8 rounded-3xl border border-black/5 bg-white p-8 text-center sm:p-12"
        >
          <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
            <.icon name="hero-academic-cap" class="h-7 w-7" />
          </span>
          <h3 class="mt-5 text-xl font-semibold text-dark">You haven't enrolled yet.</h3>
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
    </.student_layout>
    """
  end

  defp load_courses(socket) do
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

    assign(socket, :course_cards, course_cards)
  end

  defp resume_lecture(course, progress) do
    lectures = Enum.flat_map(course.modules, & &1.lectures)

    Enum.find(lectures, fn lecture ->
      case progress[lecture.id] do
        %{status: :completed} -> false
        _progress -> true
      end
    end) || List.last(lectures)
  end

  defp pluralize(1, word), do: word
  defp pluralize(_count, word), do: word <> "s"
end
