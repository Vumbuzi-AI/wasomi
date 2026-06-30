defmodule WasomiWeb.CatalogLive.Index do
  use WasomiWeb, :live_view

  import WasomiWeb.HomeComponents

  alias Wasomi.Catalog

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Courses")
     |> assign(:courses, Catalog.list_published_courses())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-soft text-dark">
      <.home_header current_user={@current_user} />

      <main>
        <section class="bg-gradient-to-b from-mint via-white to-soft py-20 lg:py-28">
          <div class="mx-auto max-w-container px-5 lg:px-8">
            <div class="mx-auto max-w-2xl text-center">
              <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                Practical learning
              </span>
              <h1 class="mt-6 text-4xl font-semibold leading-[1.1] text-dark sm:text-5xl lg:text-6xl">
                Build the human skills that move technical work forward.
              </h1>
              <p class="mt-6 text-lg text-body">
                Focused, video-based courses for technology professionals who want to communicate
                clearly, present confidently, and lead with influence.
              </p>
            </div>

            <div
              :if={@courses != []}
              id="published-courses"
              class="mt-14 grid gap-7 md:grid-cols-2 lg:grid-cols-3"
            >
              <.link
                :for={course <- @courses}
                navigate={~p"/courses/#{course.slug}"}
                class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
              >
                <div class="overflow-hidden bg-mint">
                  <img
                    src={course.thumbnail_key}
                    alt=""
                    class="h-56 w-full object-cover transition duration-500 group-hover:scale-105"
                  />
                </div>
                <div class="p-6">
                  <div class="flex items-center justify-between gap-4">
                    <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                      Communication
                    </span>
                    <span class="text-sm font-semibold text-dark">
                      {Catalog.format_price(course)}
                    </span>
                  </div>
                  <h2 class="mt-5 text-xl font-semibold text-dark">{course.title}</h2>
                  <p class="mt-3 text-body">{course.subtitle}</p>
                  <span class="mt-6 inline-flex items-center gap-2 font-medium text-primary">
                    View course <.icon name="hero-arrow-right-mini" class="h-4 w-4" />
                  </span>
                </div>
              </.link>
            </div>

            <div
              :if={@courses == []}
              id="empty-catalog"
              class="mx-auto mt-14 max-w-xl rounded-3xl border border-black/5 bg-white p-10 text-center"
            >
              <.icon name="hero-academic-cap" class="h-10 w-10 text-primary" />
              <h2 class="mt-4 text-xl font-semibold">New courses are on the way.</h2>
              <p class="mt-2 text-body">Check back soon for Wasomi's first learning experience.</p>
            </div>
          </div>
        </section>
      </main>
    </div>
    """
  end
end
