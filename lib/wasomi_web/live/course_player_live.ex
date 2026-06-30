defmodule WasomiWeb.CoursePlayerLive do
  use WasomiWeb, :live_view

  alias Wasomi.{Catalog, Certificates, Enrollments, Learning}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    course = Catalog.get_published_course_by_slug!(slug)

    case Enrollments.authorize_course(socket.assigns.current_user, course) do
      {:ok, course} ->
        if connected?(socket) do
          Learning.subscribe(socket.assigns.current_user)
          Certificates.subscribe(socket.assigns.current_user)
        end

        {:ok,
         socket
         |> assign(:page_title, course.title)
         |> assign(:course, course)
         |> refresh_progress()}

      {:error, :forbidden} ->
        {:ok,
         socket
         |> put_flash(:error, "Complete enrollment to access course content.")
         |> redirect(to: ~p"/courses/#{course.slug}/checkout")}
    end
  end

  @impl true
  def handle_event("select-lecture", %{"id" => id}, socket) do
    lecture = find_lecture(socket.assigns.course, id)

    if lecture &&
         Learning.lecture_unlocked?(socket.assigns.current_user, socket.assigns.course, lecture) do
      {:noreply,
       socket
       |> assign(:current_lecture, lecture)
       |> assign(:page_title, "#{lecture.title} · #{socket.assigns.course.title}")}
    else
      {:noreply, put_flash(socket, :error, "Complete the previous lecture to unlock this one.")}
    end
  end

  @impl true
  def handle_event(
        "video-progress",
        %{"lecture_id" => lecture_id, "position_seconds" => position},
        socket
      ) do
    with %{} = lecture <- current_lecture(socket, lecture_id),
         {:ok, _progress, _events} <-
           Learning.record_progress(socket.assigns.current_user, lecture, position) do
      {:noreply, refresh_progress(socket)}
    else
      nil ->
        {:noreply, socket}

      {:error, :forbidden} ->
        {:noreply, redirect_to_checkout(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "We couldn't save your progress.")}
    end
  end

  @impl true
  def handle_event("complete-lecture", %{"lecture_id" => lecture_id}, socket) do
    with %{} = lecture <- current_lecture(socket, lecture_id),
         {:ok, _progress, _events} <-
           Learning.mark_complete(socket.assigns.current_user, lecture) do
      {:noreply,
       socket
       |> refresh_progress()
       |> put_flash(:info, "Lecture completed. The next lesson is now unlocked.")}
    else
      nil ->
        {:noreply, socket}

      {:error, :forbidden} ->
        {:noreply, redirect_to_checkout(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "We couldn't complete this lecture.")}
    end
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
          <div class="flex flex-col gap-6">
            <div class="flex items-center justify-between gap-4">
              <span class="rounded-full bg-mint px-3 py-1 text-xs font-medium uppercase tracking-wider text-primary">
                Enrolled
              </span>
              <.link
                navigate={~p"/courses/#{@course.slug}"}
                class="inline-flex items-center gap-1.5 text-sm font-medium text-muted transition hover:text-primary"
              >
                <.icon name="hero-arrow-left" class="h-4 w-4" /> Course overview
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
            <section class="overflow-hidden rounded-3xl bg-dark">
              <%= if @current_lecture do %>
                <div
                  id={"protected-player-#{@current_lecture.id}"}
                  phx-hook="ProtectedVideo"
                  phx-update="ignore"
                  data-playback-url={~p"/media/lectures/#{@current_lecture.id}/playback"}
                  data-video-title={@current_lecture.title}
                  data-viewer-id={@current_user.id}
                  data-lecture-id={@current_lecture.id}
                  data-start-position={progress_position(@progress, @current_lecture.id)}
                  class="relative aspect-video overflow-hidden bg-black"
                  oncontextmenu="return false"
                >
                  <div
                    data-role="player"
                    class="absolute inset-0 grid place-items-center text-sm text-white/70"
                  >
                    Loading protected video…
                  </div>
                  <div
                    data-role="watermark"
                    class="pointer-events-none absolute left-[6%] top-[8%] z-20 max-w-[80%] select-none rounded-full bg-black/30 px-3 py-1 text-xs font-medium text-white/60 backdrop-blur-sm transition-all duration-1000"
                  >
                    {@current_user.email}
                  </div>
                </div>
                <div class="p-8 text-white lg:p-10">
                  <p class="text-xs font-medium uppercase tracking-widest text-primary">
                    Now playing
                  </p>
                  <h2 class="mt-3 text-2xl font-semibold tracking-tight">{@current_lecture.title}</h2>
                  <p class="mt-3 max-w-2xl leading-relaxed text-white/60">
                    {@current_lecture.description}
                  </p>

                  <div class="mt-8 flex flex-wrap items-center gap-3">
                    <button
                      :if={progress_status(@progress, @current_lecture.id) != :completed}
                      id="mark-lecture-complete"
                      type="button"
                      phx-click="complete-lecture"
                      phx-value-lecture_id={@current_lecture.id}
                      class="rounded-full bg-primary px-5 py-2.5 text-sm font-medium text-white transition hover:bg-white hover:text-dark"
                    >
                      Mark complete
                    </button>
                    <span
                      :if={progress_status(@progress, @current_lecture.id) == :completed}
                      class="inline-flex items-center gap-2 rounded-full bg-primary/20 px-4 py-2 text-sm font-medium text-white"
                    >
                      <.icon name="hero-check-circle" class="h-5 w-5 text-primary" /> Completed
                    </span>
                  </div>
                </div>
              <% else %>
                <div class="grid min-h-80 place-items-center p-8 text-center text-white/70">
                  This course does not have any lectures yet.
                </div>
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
                  </div>
                </section>
              </div>
            </aside>
          </div>

          <section
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

  defp refresh_progress(socket) do
    user = socket.assigns.current_user
    course = socket.assigns.course
    course_progress = Learning.course_progress(user, course)
    current_lecture = socket.assigns[:current_lecture] || Learning.next_lecture(user, course)

    unlocked_lecture_ids =
      course
      |> course_lectures()
      |> unlocked_lecture_ids(course_progress.progress)

    socket
    |> assign(:course_progress, course_progress)
    |> assign(:progress, course_progress.progress)
    |> assign(:unlocked_lecture_ids, unlocked_lecture_ids)
    |> assign(:current_lecture, current_lecture)
    |> refresh_certificates()
  end

  defp refresh_certificates(socket) do
    assign(
      socket,
      :certificates,
      Certificates.list_for_user_course(socket.assigns.current_user, socket.assigns.course)
    )
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

  defp unlocked_lecture_ids(lectures, progress) do
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
end
