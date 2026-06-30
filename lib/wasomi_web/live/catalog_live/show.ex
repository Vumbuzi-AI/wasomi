defmodule WasomiWeb.CatalogLive.Show do
  use WasomiWeb, :live_view

  import WasomiWeb.HomeComponents

  alias Wasomi.Catalog

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    course = Catalog.get_published_course_by_slug!(slug)

    {:ok,
     socket
     |> assign(:page_title, course.title)
     |> assign(:course, course)
     |> assign(:lecture_count, Catalog.lecture_count(course))
     |> assign(:duration_label, duration_label(Catalog.duration_seconds(course)))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white text-dark">
      <.home_header current_user={@current_user} />

      <main>
        <section class="bg-gradient-to-b from-mint via-white to-white py-16 lg:py-24">
          <div class="mx-auto grid max-w-container gap-12 px-5 lg:grid-cols-2 lg:items-center lg:px-8">
            <div>
              <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                Communication & presentation
              </span>
              <h1 class="mt-6 text-4xl font-semibold leading-[1.1] text-dark sm:text-5xl lg:text-6xl">
                {@course.title}
              </h1>
              <p class="mt-5 text-xl text-body">{@course.subtitle}</p>
              <p class="mt-6 max-w-xl text-body">{@course.description}</p>

              <div class="mt-7 flex flex-wrap gap-3 text-sm font-medium text-dark">
                <span class="rounded-full border border-black/10 bg-white px-4 py-2">
                  {length(@course.modules)} modules
                </span>
                <span class="rounded-full border border-black/10 bg-white px-4 py-2">
                  {@lecture_count} lectures
                </span>
                <span class="rounded-full border border-black/10 bg-white px-4 py-2">
                  {@duration_label}
                </span>
              </div>
            </div>

            <div class="overflow-hidden rounded-[32px] border border-black/5 bg-white shadow-2xl">
              <img src={@course.thumbnail_key} alt="" class="h-72 w-full object-cover lg:h-96" />
              <div id="enroll" class="flex items-center justify-between gap-5 p-6">
                <div>
                  <p class="text-sm text-muted">One-time course fee</p>
                  <p class="text-2xl font-semibold text-dark">{Catalog.format_price(@course)}</p>
                </div>
                <.link
                  href={
                    if @current_user,
                      do: ~p"/courses/#{@course.slug}/checkout",
                      else: ~p"/users/register"
                  }
                  class="group inline-flex items-center gap-2 rounded-full bg-dark py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
                >
                  {if @current_user, do: "Enroll & Pay", else: "Create account"}
                  <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover:bg-dark">
                    <.icon name="hero-arrow-right-mini" class="h-4 w-4" />
                  </span>
                </.link>
              </div>
            </div>
          </div>
        </section>

        <section id="curriculum" class="bg-soft py-20 lg:py-28">
          <div class="mx-auto max-w-container px-5 lg:px-8">
            <div class="mx-auto max-w-2xl text-center">
              <span class="text-sm font-semibold uppercase tracking-wider text-primary">
                Curriculum
              </span>
              <h2 class="mt-3 text-3xl font-semibold text-dark sm:text-4xl lg:text-5xl">
                A practical path from clarity to confidence.
              </h2>
              <p class="mt-5 text-lg text-body">
                Preview the complete course structure. Video playback unlocks after enrollment.
              </p>
            </div>

            <div class="mx-auto mt-12 max-w-4xl space-y-5">
              <article
                :for={module <- @course.modules}
                id={"module-#{module.id}"}
                class="rounded-3xl border border-black/5 bg-white p-6"
              >
                <div class="flex gap-5">
                  <span class="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-mint font-semibold text-primary">
                    {module.position}
                  </span>
                  <div class="min-w-0 flex-1">
                    <h3 class="text-lg font-medium text-dark">{module.title}</h3>
                    <p class="mt-2 text-body">{module.description}</p>
                    <ul class="mt-5 divide-y divide-black/5 border-t border-black/5">
                      <li
                        :for={lecture <- module.lectures}
                        class="flex items-center justify-between gap-4 py-3 text-sm"
                      >
                        <span class="flex items-center gap-3 text-dark">
                          <.icon name="hero-play-circle" class="h-5 w-5 text-primary" />
                          {lecture.title}
                        </span>
                        <span class="shrink-0 text-muted">
                          {minutes(lecture.duration_seconds)} min
                        </span>
                      </li>
                    </ul>
                  </div>
                </div>
              </article>
            </div>
          </div>
        </section>
      </main>
    </div>
    """
  end

  defp minutes(seconds), do: max(1, div(seconds + 59, 60))

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
