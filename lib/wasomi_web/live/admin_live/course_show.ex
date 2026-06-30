defmodule WasomiWeb.AdminLive.CourseShow do
  use WasomiWeb, :live_view

  alias Wasomi.{Catalog, Enrollments, Payments}
  alias Wasomi.Catalog.{CourseModule, Lecture}
  alias WasomiWeb.CourseModuleLive
  alias WasomiWeb.LectureLive

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:modal, nil)
     |> assign(:course_module, nil)
     |> assign(:lecture, nil)
     |> assign(:form_title, nil)
     |> assign(:active_tab, :curriculum)
     |> load_course(id)}
  end

  # push_patch from the module/lecture form components lands here; reload and
  # close any open modal.
  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    {:noreply, socket |> load_course(id) |> close_modal()}
  end

  @impl true
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
       position: length(module.lectures) + 1,
       video_provider: :mux
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
    {:noreply, close_modal(socket)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket)
      when tab in ["curriculum", "students"] do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  def handle_event("delete_module", %{"id" => id}, socket) do
    module = Catalog.get_course_module!(id)
    {:ok, _} = Catalog.delete_course_module(module)

    {:noreply,
     socket
     |> put_flash(:info, "Module deleted.")
     |> load_course(socket.assigns.course.id)}
  end

  def handle_event("delete_lecture", %{"id" => id}, socket) do
    lecture = Catalog.get_lecture!(id)
    {:ok, _} = Catalog.delete_lecture(lecture)

    {:noreply,
     socket
     |> put_flash(:info, "Lecture deleted.")
     |> load_course(socket.assigns.course.id)}
  end

  def handle_event("reorder_modules", %{"module_ids" => module_ids}, socket) do
    case Catalog.reorder_course_modules(socket.assigns.course.id, module_ids) do
      {:ok, _} ->
        {:noreply, load_course(socket, socket.assigns.course.id)}

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
        {:noreply, load_course(socket, socket.assigns.course.id)}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not reorder lectures. Refresh and try again.")}
    end
  end

  @impl true
  def handle_info({mod, {:saved, _record}}, socket)
      when mod in [CourseModuleLive.FormComponent, LectureLive.FormComponent] do
    {:noreply, socket |> load_course(socket.assigns.course.id) |> close_modal()}
  end

  defp close_modal(socket) do
    assign(socket, modal: nil, course_module: nil, lecture: nil, form_title: nil)
  end

  defp load_course(socket, id) do
    course = Catalog.get_course_with_outline!(id)
    enrollments = Enrollments.list_active_for_course(course.id)
    payments = Payments.list_payments_for_course(course.id)

    paid_by_user =
      payments
      |> Enum.filter(&(&1.status == :successful))
      |> Map.new(&{&1.user_id, &1})

    students =
      Enum.map(enrollments, fn enrollment ->
        %{enrollment: enrollment, payment: Map.get(paid_by_user, enrollment.user_id)}
      end)

    lecture_count = Enum.sum(Enum.map(course.modules, &length(&1.lectures)))

    socket
    |> assign(:page_title, course.title)
    |> assign(:course, course)
    |> assign(:students, students)
    |> assign(:student_count, length(enrollments))
    |> assign(:lecture_count, lecture_count)
    |> assign(:revenue_minor, Payments.revenue_minor_for_course(course.id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:courses} current_user={@current_user}>
      <div class="mx-auto max-w-container space-y-8 px-5 py-10 lg:px-10">
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
              </div>
              <h1 class="mt-4 text-3xl font-semibold leading-tight text-dark sm:text-4xl">
                {@course.title}
              </h1>
              <p class="mt-3 text-lg text-body">{@course.subtitle}</p>
              <p class="mt-4 max-w-xl text-body">{@course.description}</p>

              <div class="mt-6 flex flex-wrap items-center gap-3">
                <.link
                  navigate={~p"/admin/courses/#{@course.id}/edit"}
                  class="group inline-flex items-center gap-2 rounded-full bg-dark py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
                >
                  Edit course
                  <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover:bg-dark">
                    <.icon name="hero-pencil-square" class="h-4 w-4" />
                  </span>
                </.link>
                <.link
                  navigate={~p"/courses/#{@course.slug}"}
                  class="inline-flex items-center gap-2 rounded-full border border-dark px-5 py-2.5 text-sm font-medium text-dark transition hover:bg-dark hover:text-white"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" /> View public page
                </.link>
              </div>
            </div>

            <div class="overflow-hidden rounded-[28px] border border-black/5 bg-white shadow-2xl">
              <img src={@course.thumbnail_key} alt="" class="h-64 w-full object-cover lg:h-80" />
              <div class="flex items-center justify-between gap-4 p-6">
                <div>
                  <p class="text-sm text-muted">One-time course fee</p>
                  <p class="text-2xl font-semibold text-dark">{Catalog.format_price(@course)}</p>
                </div>
                <div class="text-right">
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
        <div class="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
          <.stat_card label="Students" value={@student_count} icon="hero-users" />
          <.stat_card
            label="Revenue"
            value={Payments.format_minor(@revenue_minor, @course.currency)}
            icon="hero-banknotes"
          />
          <.stat_card label="Modules" value={length(@course.modules)} icon="hero-rectangle-stack" />
          <.stat_card label="Lectures" value={@lecture_count} icon="hero-play-circle" />
        </div>

        <%!-- Tabs --%>
        <div class="flex items-center gap-2 rounded-full border border-black/5 bg-white p-1.5">
          <button
            type="button"
            phx-click={JS.push("switch_tab", value: %{tab: "curriculum"})}
            class={[
              "flex-1 rounded-full px-5 py-2.5 text-sm font-medium transition sm:flex-none",
              if(@active_tab == :curriculum,
                do: "bg-dark text-white",
                else: "text-muted hover:text-dark"
              )
            ]}
          >
            Curriculum
          </button>
          <button
            type="button"
            phx-click={JS.push("switch_tab", value: %{tab: "students"})}
            class={[
              "flex-1 rounded-full px-5 py-2.5 text-sm font-medium transition sm:flex-none",
              if(@active_tab == :students,
                do: "bg-dark text-white",
                else: "text-muted hover:text-dark"
              )
            ]}
          >
            Enrolled students
            <span class="ml-1.5 rounded-full bg-mint px-2 py-0.5 text-xs font-semibold text-primary">
              {@student_count}
            </span>
          </button>
        </div>

        <%!-- Curriculum (editable) --%>
        <section
          :if={@active_tab == :curriculum}
          class="rounded-3xl border border-black/5 bg-white p-6 lg:p-8"
        >
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div>
              <h2 class="text-xl font-semibold text-dark">Course curriculum</h2>
              <p class="mt-1 text-sm text-muted">Add and arrange modules and their lectures.</p>
            </div>
            <button
              type="button"
              phx-click="new_module"
              class="group inline-flex items-center gap-2 rounded-full bg-dark py-1.5 pl-5 pr-1.5 text-sm font-medium text-white transition hover:bg-primary"
            >
              Add module
              <span class="grid h-8 w-8 place-items-center rounded-full bg-primary text-white transition group-hover:bg-dark">
                <.icon name="hero-plus-mini" class="h-4 w-4" />
              </span>
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
              class="rounded-2xl border border-black/5 bg-soft/40 p-5 transition data-[dragging=true]:opacity-60 data-[drag-over=true]:border-primary data-[drag-over=true]:bg-mint/50"
            >
              <div class="flex items-start gap-4">
                <button
                  type="button"
                  data-sortable-handle
                  class="mt-1 grid h-9 w-9 shrink-0 cursor-grab place-items-center rounded-full border border-black/10 bg-white text-muted transition hover:border-primary hover:text-primary active:cursor-grabbing"
                  title="Drag module"
                  aria-label="Drag module"
                >
                  <.icon name="hero-bars-3" class="h-4 w-4" />
                </button>
                <span class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-mint font-semibold text-primary">
                  {module.position}
                </span>
                <div class="min-w-0 flex-1">
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <h3 class="font-semibold text-dark">{module.title}</h3>
                      <p :if={module.description} class="mt-1 text-sm text-body">
                        {module.description}
                      </p>
                    </div>
                    <div class="flex shrink-0 items-center gap-2">
                      <button
                        type="button"
                        phx-click={JS.push("edit_module", value: %{id: module.id})}
                        class="grid h-8 w-8 place-items-center rounded-full border border-black/10 bg-white text-muted transition hover:border-primary hover:text-primary"
                        title="Edit module"
                      >
                        <.icon name="hero-pencil-square" class="h-4 w-4" />
                      </button>
                      <button
                        type="button"
                        phx-click={JS.push("delete_module", value: %{id: module.id})}
                        data-confirm={"Delete \"#{module.title}\" and all its lectures?"}
                        class="grid h-8 w-8 place-items-center rounded-full border border-black/10 bg-white text-muted transition hover:border-red-400 hover:text-red-500"
                        title="Delete module"
                      >
                        <.icon name="hero-trash" class="h-4 w-4" />
                      </button>
                    </div>
                  </div>

                  <ul
                    id={"module-#{module.id}-lectures"}
                    phx-hook="SortableList"
                    data-event="reorder_lectures"
                    data-parent-key="module_id"
                    data-parent-id={module.id}
                    data-order-key="lecture_ids"
                    class="mt-4 space-y-2"
                  >
                    <li
                      :for={lecture <- module.lectures}
                      id={"lecture-#{lecture.id}"}
                      data-sortable-item
                      data-id={lecture.id}
                      draggable="false"
                      class="flex items-center justify-between gap-3 rounded-xl border border-black/5 bg-white px-4 py-2.5 transition data-[dragging=true]:opacity-60 data-[drag-over=true]:border-primary data-[drag-over=true]:bg-mint/50"
                    >
                      <span class="flex min-w-0 items-center gap-3 text-sm text-dark">
                        <button
                          type="button"
                          data-sortable-handle
                          class="grid h-7 w-7 shrink-0 cursor-grab place-items-center rounded-full text-muted transition hover:bg-mint hover:text-primary active:cursor-grabbing"
                          title="Drag lecture"
                          aria-label="Drag lecture"
                        >
                          <.icon name="hero-bars-3" class="h-4 w-4" />
                        </button>
                        <.icon name="hero-play-circle" class="h-5 w-5 shrink-0 text-primary" />
                        <span class="truncate">{lecture.title}</span>
                        <span class="shrink-0 text-xs text-muted">
                          {minutes(lecture.duration_seconds)} min
                        </span>
                      </span>
                      <span class="flex shrink-0 items-center gap-1.5">
                        <button
                          type="button"
                          phx-click={JS.push("edit_lecture", value: %{id: lecture.id})}
                          class="grid h-8 w-8 place-items-center rounded-full text-muted transition hover:bg-mint hover:text-primary"
                          title="Edit lecture"
                        >
                          <.icon name="hero-pencil-square" class="h-4 w-4" />
                        </button>
                        <button
                          type="button"
                          phx-click={JS.push("delete_lecture", value: %{id: lecture.id})}
                          data-confirm={"Delete lecture \"#{lecture.title}\"?"}
                          class="grid h-8 w-8 place-items-center rounded-full text-muted transition hover:bg-red-50 hover:text-red-500"
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

                  <button
                    type="button"
                    phx-click={JS.push("new_lecture", value: %{"module-id" => module.id})}
                    class="mt-3 inline-flex items-center gap-1.5 text-sm font-medium text-primary transition hover:text-dark"
                  >
                    <.icon name="hero-plus-circle" class="h-4 w-4" /> Add lecture
                  </button>
                </div>
              </div>
            </article>
          </div>

          <div
            :if={@course.modules == []}
            class="mt-6 rounded-2xl border border-dashed border-black/10 bg-soft/40 p-10 text-center"
          >
            <span class="mx-auto grid h-12 w-12 place-items-center rounded-full bg-mint text-primary">
              <.icon name="hero-rectangle-stack" class="h-6 w-6" />
            </span>
            <p class="mt-4 font-medium text-dark">No modules yet</p>
            <p class="mt-1 text-sm text-body">
              Add your first module to start building the curriculum.
            </p>
          </div>
        </section>

        <%!-- Enrolled students --%>
        <section
          :if={@active_tab == :students}
          class="rounded-3xl border border-black/5 bg-white p-6 lg:p-8"
        >
          <h2 class="text-xl font-semibold text-dark">Enrolled students</h2>

          <div :if={@students != []} class="mt-5 overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead class="border-b border-black/5 text-xs uppercase tracking-wide text-muted">
                <tr>
                  <th class="py-3 pr-4 font-semibold">Student</th>
                  <th class="py-3 pr-4 font-semibold">Enrolled</th>
                  <th class="py-3 text-right font-semibold">Paid</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-black/5">
                <tr :for={row <- @students}>
                  <td class="py-3 pr-4">
                    <.link
                      navigate={~p"/admin/students/#{row.enrollment.user_id}"}
                      class="font-medium text-dark hover:text-primary"
                    >
                      {row.enrollment.user.name || "Learner"}
                    </.link>
                    <p class="text-xs text-muted">{row.enrollment.user.email}</p>
                  </td>
                  <td class="py-3 pr-4 text-body">{format_date(row.enrollment.activated_at)}</td>
                  <td class="py-3 text-right font-semibold text-dark">
                    {if row.payment, do: Payments.format_amount(row.payment), else: "—"}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <p :if={@students == []} class="mt-5 rounded-2xl bg-soft p-5 text-body">
            No students have enrolled in this course yet.
          </p>
        </section>
      </div>

      <%!-- Module modal --%>
      <.modal :if={@modal == :module} id="module-modal" show on_cancel={JS.push("close_modal")}>
        <.live_component
          module={CourseModuleLive.FormComponent}
          id={@course_module.id || :new_module}
          title={@form_title}
          action={if @course_module.id, do: :edit, else: :new}
          course_module={@course_module}
          patch={~p"/admin/courses/#{@course.id}"}
        />
      </.modal>

      <%!-- Lecture modal --%>
      <.modal :if={@modal == :lecture} id="lecture-modal" show on_cancel={JS.push("close_modal")}>
        <.live_component
          module={LectureLive.FormComponent}
          id={@lecture.id || :new_lecture}
          title={@form_title}
          action={if @lecture.id, do: :edit, else: :new}
          lecture={@lecture}
          current_user={@current_user}
          patch={~p"/admin/courses/#{@course.id}"}
        />
      </.modal>
    </.admin_layout>
    """
  end

  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) when is_binary(value), do: String.to_integer(value)

  defp minutes(seconds) when is_integer(seconds), do: max(1, div(seconds + 59, 60))
  defp minutes(_), do: 0

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")
  defp format_date(_), do: "—"
end
