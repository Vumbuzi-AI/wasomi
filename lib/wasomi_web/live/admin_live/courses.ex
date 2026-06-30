defmodule WasomiWeb.AdminLive.Courses do
  use WasomiWeb, :live_view

  alias Wasomi.{Catalog, Enrollments, Payments}
  alias Wasomi.Catalog.Course
  alias WasomiWeb.CourseLive.FormComponent

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Courses")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, socket |> apply_action(socket.assigns.live_action, params) |> load_courses()}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, course: nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:course, %Course{currency: "KES", status: :draft, position: next_position(socket)})
    |> assign(:form_title, "New course")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:course, Catalog.get_course!(id))
    |> assign(:form_title, "Edit course")
  end

  defp next_position(_socket), do: Catalog.count_courses() + 1

  @impl true
  def handle_info({FormComponent, {:saved, _course}}, socket) do
    {:noreply, load_courses(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    course = Catalog.get_course!(id)

    case Catalog.delete_course(course) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Course deleted.") |> load_courses()}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not delete this course. It may still have enrollments or payments attached."
         )}
    end
  end

  defp load_courses(socket) do
    revenue = Payments.revenue_minor_by_course()
    enrollments = Enrollments.count_active_by_course()

    rows =
      Catalog.list_courses()
      |> Enum.map(fn course ->
        %{
          course: course,
          students: Map.get(enrollments, course.id, 0),
          revenue_minor: Map.get(revenue, course.id, 0)
        }
      end)

    assign(socket, :rows, rows)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:courses} current_user={@current_user}>
      <div class="mx-auto max-w-container space-y-8 px-5 py-10 lg:px-10">
        <.page_header eyebrow="Catalog" title="Courses">
          <:subtitle>Create, edit and track the performance of every course.</:subtitle>
          <:actions>
            <.link
              patch={~p"/admin/courses/new"}
              class="group inline-flex items-center gap-2 rounded-full bg-dark py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
            >
              New course
              <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover:bg-dark">
                <.icon name="hero-plus-mini" class="h-4 w-4" />
              </span>
            </.link>
          </:actions>
        </.page_header>

        <div :if={@rows != []} class="grid gap-7 sm:grid-cols-2 xl:grid-cols-3">
          <article
            :for={row <- @rows}
            id={"course-row-#{row.course.id}"}
            class="group relative flex flex-col overflow-hidden rounded-3xl border border-black/5 bg-white shadow-sm transition duration-300 hover:-translate-y-1 hover:shadow-xl"
          >
            <div class="relative aspect-[16/10] overflow-hidden bg-mint">
              <img
                src={row.course.thumbnail_key}
                alt=""
                class="h-full w-full object-cover transition duration-500 group-hover:scale-105"
              />
              <div class="absolute inset-0 bg-gradient-to-t from-dark/30 via-transparent to-transparent">
              </div>
              <span class="absolute left-4 top-4">
                <.status_badge status={row.course.status} />
              </span>
              <div class="absolute right-4 top-4 z-10 flex items-center gap-2">
                <.link
                  patch={~p"/admin/courses/#{row.course.id}/edit"}
                  class="grid h-9 w-9 place-items-center rounded-full bg-white/95 text-dark shadow-sm backdrop-blur transition hover:bg-white hover:text-primary"
                  title="Edit course"
                >
                  <.icon name="hero-pencil-square" class="h-4 w-4" />
                </.link>
                <.link
                  phx-click={JS.push("delete", value: %{id: row.course.id})}
                  data-confirm={"Delete \"#{row.course.title}\"? This cannot be undone."}
                  class="grid h-9 w-9 place-items-center rounded-full bg-white/95 text-dark shadow-sm backdrop-blur transition hover:bg-white hover:text-red-500"
                  title="Delete course"
                >
                  <.icon name="hero-trash" class="h-4 w-4" />
                </.link>
              </div>
            </div>

            <div class="flex flex-1 flex-col p-6">
              <.link
                navigate={~p"/admin/courses/#{row.course.id}"}
                class="text-lg font-semibold leading-snug text-dark after:absolute after:inset-0 group-hover:text-primary"
              >
                {row.course.title}
              </.link>
              <p class="mt-1 text-sm text-muted">/{row.course.slug}</p>
              <p :if={row.course.subtitle} class="mt-3 line-clamp-2 text-sm text-body">
                {row.course.subtitle}
              </p>

              <dl class=" mt-4 divide-y divide-black/5 rounded-2xl bg-soft px-4">
                <.metric label="Price" value={Catalog.format_price(row.course)} />
                <.metric label="Students" value={row.students} />
                <.metric
                  label="Revenue"
                  value={Payments.format_minor(row.revenue_minor, row.course.currency)}
                  accent
                />
              </dl>
            </div>
          </article>
        </div>

        <div :if={@rows == []} class="rounded-3xl border border-black/5 bg-white p-12 text-center">
          <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
            <.icon name="hero-academic-cap" class="h-7 w-7" />
          </span>
          <h3 class="mt-5 text-xl font-semibold text-dark">No courses yet</h3>
          <p class="mx-auto mt-2 max-w-md text-body">
            Create your first course to start enrolling learners and earning revenue.
          </p>
          <.link
            patch={~p"/admin/courses/new"}
            class="mt-6 inline-flex rounded-full bg-dark px-6 py-3 font-medium text-white transition hover:bg-primary"
          >
            New course
          </.link>
        </div>
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="course-modal"
        show
        on_cancel={JS.patch(~p"/admin/courses")}
      >
        <.live_component
          module={FormComponent}
          id={@course.id || :new}
          title={@form_title}
          action={@live_action}
          course={@course}
          patch={~p"/admin/courses"}
        />
      </.modal>
    </.admin_layout>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :accent, :boolean, default: false

  defp metric(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3 py-2.5">
      <dt class="text-xs font-medium uppercase tracking-wide text-muted">{@label}</dt>
      <dd class={["text-sm font-semibold", if(@accent, do: "text-primary", else: "text-dark")]}>
        {@value}
      </dd>
    </div>
    """
  end
end
