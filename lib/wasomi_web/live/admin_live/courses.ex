defmodule WasomiWeb.AdminLive.Courses do
  use WasomiWeb, :live_view

  alias Wasomi.{Catalog, Enrollments, Learning, Paginate, Payments}
  alias Wasomi.Catalog.{Course, PublishGuard}
  alias WasomiWeb.CourseLive.FormComponent

  @status_values Ecto.Enum.values(Course, :status)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Courses")
     |> assign(:status_values, @status_values)
     |> assign(:archiving_course, nil)
     |> assign(:incomplete_enrollee_count, 0)
     |> assign(:publish_checklist_course, nil)
     |> assign(:publish_checklist, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(publish_checklist_course: nil, publish_checklist: nil)
     |> apply_action(socket.assigns.live_action, params)
     |> assign(:status_filter, parse_status(params["status"]))
     |> assign(:search, params["q"] || "")
     |> assign(:page_number, Paginate.parse_page(params["page"]))
     |> load_courses()}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, course: nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:course, %Course{currency: "KES", status: :draft, position: next_position(socket)})
    |> assign(:form_title, "New course")
  end

  defp apply_action(socket, :edit, %{"slug" => slug}) do
    socket
    |> assign(:course, Catalog.get_course_by_slug!(slug))
    |> assign(:form_title, "Edit course")
  end

  defp next_position(_socket), do: Catalog.count_courses() + 1

  defp parse_status(value), do: Enum.find(@status_values, &(Atom.to_string(&1) == value))

  @impl true
  def handle_info({FormComponent, {:saved, _course}}, socket) do
    {:noreply, load_courses(socket)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, push_patch(socket, to: courses_path(socket.assigns.status_filter, query))}
  end

  def handle_event("publish_course", %{"id" => id}, socket) do
    course = Catalog.get_course!(id)

    case Catalog.publish_course(course) do
      {:ok, _course} ->
        {:noreply,
         socket
         |> put_flash(:info, "Course published — it's now visible in the public catalog.")
         |> load_courses()}

      {:error, issues} when is_list(issues) ->
        checklist = course.id |> Catalog.get_course_with_outline!() |> PublishGuard.checklist()

        {:noreply,
         socket
         |> assign(:publish_checklist_course, course)
         |> assign(:publish_checklist, checklist)}
    end
  end

  def handle_event("close_publish_checklist", _params, socket) do
    {:noreply, assign(socket, publish_checklist_course: nil, publish_checklist: nil)}
  end

  def handle_event("confirm_archive_course", %{"id" => id}, socket) do
    course = Catalog.get_course!(id)

    {:noreply,
     socket
     |> assign(:archiving_course, course)
     |> assign(:incomplete_enrollee_count, Learning.count_incomplete_enrollees(course))}
  end

  def handle_event("cancel_archive_course", _params, socket) do
    {:noreply, assign(socket, :archiving_course, nil)}
  end

  def handle_event("archive_course", %{"id" => id}, socket) do
    {:ok, _course} = Catalog.archive_course(Catalog.get_course!(id))

    {:noreply,
     socket
     |> put_flash(:info, "Course archived — it's no longer visible in the public catalog.")
     |> assign(:archiving_course, nil)
     |> load_courses()}
  end

  defp courses_path(status, search, page \\ 1) do
    params =
      %{status: status, q: search, page: page}
      |> Enum.reject(fn
        {:page, 1} -> true
        {_key, value} -> value in [nil, ""]
      end)

    ~p"/admin/courses?#{params}"
  end

  defp load_courses(socket) do
    revenue = Payments.revenue_minor_by_course()
    enrollments = Enrollments.count_active_by_course()

    page =
      Catalog.list_courses_page(
        status: socket.assigns.status_filter,
        search: socket.assigns.search,
        page: socket.assigns.page_number
      )

    rows =
      Enum.map(page.entries, fn course ->
        %{
          course: course,
          students: Map.get(enrollments, course.id, 0),
          revenue_minor: Map.get(revenue, course.id, 0)
        }
      end)

    socket
    |> assign(:rows, rows)
    |> assign(:page, page)
    |> assign(:stats, Catalog.course_stats())
    |> assign(:total_active_learners, Enrollments.count_active())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:courses} current_user={@current_user}>
      <div class="mx-auto max-w-container space-y-8 px-5 py-10 lg:px-10">
        <.page_header title="Courses">
          <:subtitle>Create, edit and track the performance of every course.</:subtitle>
          <:actions>
            <.search_input value={@search} placeholder="Search course or slug" />
            <.link
              patch={~p"/admin/courses/new"}
              class="group flex h-11 items-center gap-2 rounded-full bg-dark py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
            >
              New course
              <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover:bg-dark">
                <.icon name="hero-plus-mini" class="h-4 w-4" />
              </span>
            </.link>
          </:actions>
        </.page_header>

        <div class="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
          <.stat_card
            label="Total courses"
            value={@stats.total}
            icon="hero-rectangle-stack"
            hint="All catalogue records"
          />
          <.stat_card
            label="Published"
            value={@stats.published}
            icon="hero-check-circle"
            hint="Visible to learners"
          />
          <.stat_card
            label="Draft"
            value={@stats.draft}
            icon="hero-pencil-square"
            hint="Still being prepared"
          />
          <.stat_card
            label="Learners"
            value={@total_active_learners}
            icon="hero-users"
            hint="Across all courses"
          />
        </div>

        <div class="rounded-[2rem] border border-black/5 bg-white p-6 shadow-sm lg:p-8">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div>
              <h2 class="text-xl font-semibold text-dark">Course catalogue</h2>
              <p class="mt-1 text-sm text-body">Review content, price, learner count and revenue.</p>
            </div>
            <span class="rounded-full border border-primary/30 bg-mint px-3 py-1 text-xs font-semibold text-primary">
              {@page.total_count} {ngettext("course", "courses", @page.total_count)}
            </span>
          </div>

          <div class="mt-6 flex flex-wrap gap-2">
            <.link patch={courses_path(nil, @search)} class={filter_pill_class(@status_filter == nil)}>
              All courses
            </.link>
            <.link
              :for={status <- @status_values}
              patch={courses_path(status, @search)}
              class={filter_pill_class(@status_filter == status)}
            >
              {humanize_status(status)}
            </.link>
          </div>

          <div class="mt-6">
            <.paginated_table
              page={@page.page}
              total_pages={@page.total_pages}
              path_fn={&courses_path(@status_filter, @search, &1)}
            >
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
                        patch={~p"/admin/courses/#{row.course.slug}/edit"}
                        class="grid h-9 w-9 place-items-center rounded-full bg-white/95 text-dark shadow-sm backdrop-blur transition hover:bg-white hover:text-primary"
                        title="Edit course"
                      >
                        <.icon name="hero-pencil-square" class="h-4 w-4" />
                      </.link>
                      <button
                        :if={row.course.status == :draft}
                        type="button"
                        phx-click={JS.push("publish_course", value: %{id: row.course.id})}
                        class="grid h-9 w-9 place-items-center rounded-full bg-white/95 text-dark shadow-sm backdrop-blur transition hover:bg-white hover:text-primary"
                        title="Publish course"
                      >
                        <.icon name="hero-paper-airplane" class="h-4 w-4" />
                      </button>
                      <button
                        :if={row.course.status == :published}
                        type="button"
                        phx-click={JS.push("confirm_archive_course", value: %{id: row.course.id})}
                        class="grid h-9 w-9 place-items-center rounded-full bg-white/95 text-dark shadow-sm backdrop-blur transition hover:bg-white hover:text-red-500"
                        title="Archive course"
                      >
                        <.icon name="hero-archive-box" class="h-4 w-4" />
                      </button>
                    </div>
                  </div>

                  <div class="flex flex-1 flex-col p-6">
                    <.link
                      navigate={~p"/admin/courses/#{row.course.slug}"}
                      class="text-lg font-semibold leading-snug text-dark after:absolute after:inset-0 group-hover:text-primary"
                    >
                      {row.course.title}
                    </.link>
                    <p class="mt-1 text-sm text-muted">/{row.course.slug}</p>

                    <dl class=" mt-4 divide-y divide-black/5 rounded-2xl bg-neutral-50 px-4">
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

              <div
                :if={@rows == [] and @stats.total == 0}
                class="rounded-3xl border border-black/5 bg-neutral-50 p-12 text-center"
              >
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

              <div
                :if={@rows == [] and @stats.total > 0}
                class="rounded-3xl border border-black/5 bg-neutral-50 p-12 text-center"
              >
                <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
                  <.icon name="hero-magnifying-glass" class="h-7 w-7" />
                </span>
                <h3 class="mt-5 text-xl font-semibold text-dark">No matching courses</h3>
                <p class="mx-auto mt-2 max-w-md text-body">
                  Try a different search term or clear the status filter.
                </p>
                <.link
                  patch={~p"/admin/courses"}
                  class="mt-6 inline-flex rounded-full border border-black/10 px-6 py-3 font-medium text-dark transition hover:border-primary hover:text-primary"
                >
                  Clear filters
                </.link>
              </div>
            </.paginated_table>
          </div>
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
          patch={fn _course -> ~p"/admin/courses" end}
        />
      </.modal>

      <.confirm_modal
        :if={@archiving_course}
        id="archive-course-modal"
        title={"Archive \"#{@archiving_course.title}\"?"}
        confirm_label="Archive"
        confirm={JS.push("archive_course", value: %{id: @archiving_course.id})}
        cancel={JS.push("cancel_archive_course")}
      >
        {archive_confirmation_copy(@incomplete_enrollee_count)}
      </.confirm_modal>

      <.modal
        :if={@publish_checklist_course}
        id="publish-checklist-modal"
        show
        on_cancel={JS.push("close_publish_checklist")}
      >
        <h2 class="text-lg font-semibold text-dark">
          "{@publish_checklist_course.title}" isn't ready to publish yet
        </h2>
        <p class="mt-1 text-sm text-body">Here's what's blocking it.</p>
        <.publish_checklist stages={@publish_checklist} />
        <div class="mt-6 flex items-center gap-4">
          <.link
            patch={~p"/admin/courses/#{@publish_checklist_course.slug}/edit"}
            class="rounded-full bg-dark px-5 py-2 text-sm font-medium text-white transition hover:bg-primary"
          >
            Edit course
          </.link>
          <button
            type="button"
            phx-click="close_publish_checklist"
            class="text-sm font-medium text-muted hover:text-dark"
          >
            Close
          </button>
        </div>
      </.modal>
    </.admin_layout>
    """
  end

  defp filter_pill_class(active?) do
    [
      "rounded-full px-4 py-2 text-sm font-medium transition",
      if(active?,
        do: "bg-dark text-white",
        else: "border border-black/10 bg-white text-body hover:border-primary hover:text-primary"
      )
    ]
  end

  defp humanize_status(status) do
    status
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :accent, :boolean, default: false

  defp metric(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3 py-2.5">
      <dt class="text-xs font-medium uppercase tracking-wide text-body">{@label}</dt>
      <dd class={["text-sm font-semibold", if(@accent, do: "text-primary", else: "text-dark")]}>
        {@value}
      </dd>
    </div>
    """
  end
end
