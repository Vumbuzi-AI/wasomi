defmodule WasomiWeb.CatalogLive.Show do
  use WasomiWeb, :live_view

  import WasomiWeb.HomeComponents

  alias Phoenix.LiveView.JS
  alias Wasomi.{Catalog, Enrollments}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    course = Catalog.get_published_course_by_slug!(slug)

    {:ok,
     socket
     |> assign(:page_title, course.title)
     |> assign(:course, course)
     |> assign(:lecture_count, Catalog.lecture_count(course))
     |> assign(:duration_label, duration_label(Catalog.duration_seconds(course)))
     |> assign(:learner_count, Enrollments.count_active_for_course(course.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white text-ink">
      <.home_header current_user={@current_user} />

      <main>
        <section class="bg-white py-8 lg:py-10">
          <div class="mx-auto max-w-container px-5 lg:px-8">
            <.link
              navigate={~p"/courses"}
              class="inline-flex items-center gap-1.5 text-sm font-semibold text-muted transition hover:text-ink"
            >
              <.icon name="hero-arrow-left" class="h-4 w-4" /> Back to all courses
            </.link>

            <div class="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1fr)_380px] lg:items-stretch">
              <div class="grid overflow-hidden rounded-3xl border border-black/5 bg-white shadow-sm sm:grid-cols-[280px_minmax(0,1fr)]">
                <div class="relative aspect-[4/3] bg-ink sm:aspect-auto sm:h-full">
                  <img
                    :if={@course.thumbnail_key}
                    src={@course.thumbnail_key}
                    alt=""
                    class="absolute inset-0 h-full w-full object-cover"
                  />
                </div>

                <div class="flex flex-col justify-center p-6 sm:p-8">
                  <h1 class="text-3xl font-bold leading-tight text-ink sm:text-4xl">
                    {@course.title}
                  </h1>
                  <p class="mt-4 text-body">{@course.description}</p>
                </div>
              </div>

              <div id="enroll" class="rounded-3xl border border-black/5 bg-white p-6 shadow-sm">
                <p class="text-xs font-semibold uppercase tracking-wider text-muted">
                  Course fee
                </p>
                <p class="mt-1 text-3xl font-bold text-ink">{Catalog.format_price(@course)}</p>

                <dl class="mt-5 grid grid-cols-2 gap-x-4 gap-y-5 border-t border-black/5 pt-5">
                  <div class="flex items-center gap-3">
                    <span class="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-mint text-primary">
                      <.icon name="hero-squares-2x2" class="h-4 w-4" />
                    </span>
                    <div class="min-w-0">
                      <dt class="text-xs text-muted">Modules</dt>
                      <dd class="truncate font-semibold text-ink">{length(@course.modules)}</dd>
                    </div>
                  </div>
                  <div class="flex items-center gap-3">
                    <span class="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-mint text-primary">
                      <.icon name="hero-play-circle" class="h-4 w-4" />
                    </span>
                    <div class="min-w-0">
                      <dt class="text-xs text-muted">Lessons</dt>
                      <dd class="truncate font-semibold text-ink">{@lecture_count}</dd>
                    </div>
                  </div>
                  <div class="flex items-center gap-3">
                    <span class="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-mint text-primary">
                      <.icon name="hero-clock" class="h-4 w-4" />
                    </span>
                    <div class="min-w-0">
                      <dt class="text-xs text-muted">Duration</dt>
                      <dd class="truncate font-semibold text-ink">{@duration_label}</dd>
                    </div>
                  </div>
                  <div class="flex items-center gap-3">
                    <span class="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-mint text-primary">
                      <.icon name="hero-users" class="h-4 w-4" />
                    </span>
                    <div class="min-w-0">
                      <dt class="text-xs text-muted">Learners</dt>
                      <dd class="truncate font-semibold text-ink">{@learner_count}</dd>
                    </div>
                  </div>
                  <div :if={@course.certificate_enabled} class="col-span-2 flex items-center gap-3">
                    <span class="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-mint text-primary">
                      <.icon name="hero-trophy" class="h-4 w-4" />
                    </span>
                    <div class="min-w-0">
                      <dt class="text-xs text-muted">Certificate</dt>
                      <dd class="truncate font-semibold text-ink">Included on completion</dd>
                    </div>
                  </div>
                </dl>

                <.link
                  href={
                    if @current_user,
                      do: ~p"/courses/#{@course.slug}/checkout",
                      else: ~p"/users/register"
                  }
                  class="group mt-6 flex items-center justify-between gap-2 rounded-full bg-ink py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
                >
                  {if @current_user,
                    do: if(@course.is_free, do: "Enroll for Free", else: "Enroll & Pay"),
                    else: "Create account"}
                  <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover:bg-ink">
                    <.icon name="hero-arrow-right-mini" class="h-4 w-4" />
                  </span>
                </.link>
              </div>
            </div>
          </div>
        </section>

        <section id="how-it-works" class="bg-white py-8 lg:py-10">
          <div class="mx-auto max-w-container px-5 lg:px-8">
            <h2 class="text-3xl font-semibold text-ink sm:text-4xl">How learning works</h2>

            <dl class="mt-8 grid gap-x-8 sm:grid-cols-2">
              <div class="flex items-center gap-4 border-b border-black/5 py-4 sm:py-5">
                <span class="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-primary text-white">
                  <.icon name="hero-book-open" class="h-5 w-5" />
                </span>
                <dt class="text-body">Follow the modules in order or study at your own pace.</dt>
              </div>
              <div class="flex items-center gap-4 border-b border-black/5 py-4 sm:py-5">
                <span class="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-primary text-white">
                  <.icon name="hero-clock" class="h-5 w-5" />
                </span>
                <dt class="text-body">See every lesson title and duration before enrolment.</dt>
              </div>
              <div class="flex items-center gap-4 border-b border-black/5 py-4 sm:border-b-0 sm:py-5">
                <span class="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-primary text-white">
                  <.icon name="hero-check-circle" class="h-5 w-5" />
                </span>
                <dt class="text-body">
                  {if @course.certificate_enabled,
                    do: "Complete the required lessons and checks for certification.",
                    else: "Complete the required lessons and checks to finish the course."}
                </dt>
              </div>
              <div class="flex items-center gap-4 py-4 sm:py-5">
                <span class="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-primary text-white">
                  <.icon name="hero-device-phone-mobile" class="h-5 w-5" />
                </span>
                <dt class="text-body">Learn on desktop, tablet or mobile.</dt>
              </div>
            </dl>
          </div>
        </section>

        <section :if={@course.certificate_enabled} id="certificate" class="bg-white py-8 lg:py-10">
          <div class="mx-auto max-w-container px-5 lg:px-8">
            <div class="grid gap-8 lg:grid-cols-[2fr_3fr] lg:gap-16">
              <div class="flex flex-col justify-center">
                <h2 class="text-3xl font-semibold text-ink sm:text-4xl">Certificate</h2>
                <p class="mt-4 max-w-md text-body">
                  Your certificate shows your name, this course title and the completion date
                  after you finish the required lessons and checks.
                </p>
                <ul class="mt-6 space-y-3">
                  <li class="flex items-center gap-2.5 text-sm font-medium text-ink">
                    <.icon name="hero-check" class="h-4 w-4 shrink-0 text-green-600" />
                    {@course.title}
                  </li>
                  <li class="flex items-center gap-2.5 text-sm font-medium text-ink">
                    <.icon name="hero-check" class="h-4 w-4 shrink-0 text-green-600" />
                    Downloadable after completion
                  </li>
                  <li class="flex items-center gap-2.5 text-sm font-medium text-ink">
                    <.icon name="hero-check" class="h-4 w-4 shrink-0 text-green-600" />
                    Suitable for a portfolio or training record
                  </li>
                </ul>
              </div>

              <div class="flex items-center bg-soft p-6 sm:p-10">
                <div class="w-full rounded-2xl border-2 border-ink/80 p-1">
                  <div class="rounded-xl border border-ink/30 px-6 py-10 text-center sm:px-10">
                    <span class="mx-auto grid h-12 w-12 place-items-center rounded-full bg-primary text-white">
                      <.icon name="hero-academic-cap" class="h-6 w-6" />
                    </span>
                    <p class="mt-3 text-xs font-semibold uppercase tracking-widest text-muted">
                      Wasomi · {@course.certificate_issuer_name || "Business Institute"}
                    </p>
                    <h3 class="mt-4 font-serif text-2xl font-semibold text-ink sm:text-3xl">
                      Certificate of Completion
                    </h3>
                    <p class="mt-4 text-sm text-muted">This confirms successful completion of</p>
                    <p class="mt-1 text-xl font-bold text-primary sm:text-2xl">{@course.title}</p>

                    <p class="mx-auto mt-8 max-w-[220px] border-b border-ink/30 pb-1.5 font-serif italic text-body">
                      Learner name
                    </p>

                    <div class="mt-6 flex items-center justify-between text-xs text-muted">
                      <span>{@course.certificate_signatory_name || "Course team"}</span>
                      <span>Completion date</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section id="curriculum" class="bg-white py-8 lg:py-10">
          <div class="mx-auto max-w-container px-5 lg:px-8">
            <div>
              <div class="flex flex-wrap items-end justify-between gap-4">
                <h2 class="text-3xl font-semibold text-ink sm:text-4xl">Modules</h2>
                <p class="text-sm font-medium text-muted">
                  {length(@course.modules)} modules · {@lecture_count} lessons
                </p>
              </div>

              <div class="mt-8 space-y-4">
                <div
                  :for={{module, index} <- Enum.with_index(@course.modules, 1)}
                  id={"module-#{module.id}"}
                  class={[
                    "overflow-hidden rounded-3xl border bg-white transition-colors",
                    if(index == 1, do: "border-primary", else: "border-black/5")
                  ]}
                >
                  <button
                    type="button"
                    phx-click={
                      JS.toggle(
                        to: "#module-#{module.id}-panel",
                        in:
                          {"transition-all ease-out duration-200", "opacity-0 -translate-y-1",
                           "opacity-100 translate-y-0"},
                        out:
                          {"transition-all ease-in duration-150", "opacity-100 translate-y-0",
                           "opacity-0 -translate-y-1"}
                      )
                      |> JS.toggle_class("rotate-180 bg-primary border-primary text-white",
                        to: "#module-#{module.id}-chevron"
                      )
                      |> JS.toggle_class("border-primary", to: "#module-#{module.id}")
                    }
                    class="flex w-full cursor-pointer items-start justify-between gap-4 p-6 text-left"
                  >
                    <div class="flex items-start gap-4">
                      <span class="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-ink text-sm font-semibold text-white">
                        {String.pad_leading(to_string(index), 2, "0")}
                      </span>
                      <div>
                        <h3 class="font-semibold text-ink">{index}. {module.title}</h3>
                        <p class="mt-1 text-sm text-body">{module.description}</p>
                      </div>
                    </div>

                    <div class="flex shrink-0 items-center gap-4">
                      <span class="hidden items-center gap-1.5 text-sm text-muted sm:flex">
                        <.icon name="hero-book-open" class="h-4 w-4 text-primary" />
                        {length(module.lectures)} lessons
                      </span>
                      <span class="hidden items-center gap-1.5 text-sm text-muted sm:flex">
                        <.icon name="hero-clock" class="h-4 w-4 text-primary" />
                        {duration_label(module_duration(module))}
                      </span>
                      <span
                        id={"module-#{module.id}-chevron"}
                        class={[
                          "grid h-9 w-9 shrink-0 place-items-center rounded-full border transition duration-200",
                          if(index == 1,
                            do: "rotate-180 border-primary bg-primary text-white",
                            else: "border-black/10 text-muted"
                          )
                        ]}
                      >
                        <.icon name="hero-chevron-down" class="h-4 w-4" />
                      </span>
                    </div>
                  </button>

                  <div id={"module-#{module.id}-panel"} class={index != 1 && "hidden"}>
                    <ul class="divide-y divide-black/5 border-t border-black/5 bg-soft/60 px-6">
                      <li
                        :for={lecture <- module.lectures}
                        class="flex items-center justify-between gap-4 py-4"
                      >
                        <span class="flex items-center gap-3 text-sm font-medium text-ink">
                          <.icon name="hero-lock-closed" class="h-4 w-4 text-muted" />
                          {lecture.title}
                        </span>
                        <span class="shrink-0 text-sm text-muted">
                          {minutes(lecture.duration_seconds)} min
                        </span>
                      </li>
                    </ul>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section class="bg-white py-8 lg:py-10">
          <div class="mx-auto max-w-container px-5 lg:px-8">
            <div class="flex flex-col items-start justify-between gap-5 rounded-3xl bg-ink px-6 py-6 sm:flex-row sm:items-center sm:px-10 sm:py-8">
              <h2 class="text-2xl font-semibold text-white sm:text-3xl">
                Start {@course.title}
              </h2>
              <.link
                href={
                  if @current_user,
                    do: ~p"/courses/#{@course.slug}/checkout",
                    else: ~p"/users/register"
                }
                class="group inline-flex shrink-0 items-center gap-2 rounded-full border border-white/30 py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-white hover:text-ink"
              >
                {if @current_user, do: "Enroll & Pay", else: "Create account"}
                <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover:bg-ink">
                  <.icon name="hero-arrow-right-mini" class="h-4 w-4" />
                </span>
              </.link>
            </div>
          </div>
        </section>
      </main>
    </div>
    """
  end

  defp minutes(seconds), do: max(1, div(seconds + 59, 60))

  defp module_duration(module) do
    module.lectures
    |> Enum.map(&(&1.duration_seconds || 0))
    |> Enum.sum()
  end

  defp duration_label(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    case {hours, minutes} do
      {0, minutes} -> "#{minutes} min"
      {hours, 0} -> "#{hours} hr"
      {hours, minutes} -> "#{hours} hr #{minutes} min"
    end
  end
end
