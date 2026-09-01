defmodule WasomiWeb.CatalogLive.Index do
  use WasomiWeb, :live_view

  import WasomiWeb.HomeComponents

  alias Wasomi.Catalog
  alias Wasomi.Paginate

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "GS1 Courses")
     |> assign(
       :meta_description,
       "Explore Wasomi's practical GS1 courses, compare learning outcomes and choose the right course for your goals."
     )
     |> assign(:meta_robots, "index, follow")
     |> assign(:canonical_url, url(~p"/courses"))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search = params["search"] || ""
    price = normalize_price(params["price"])
    page_number = Paginate.parse_page(params["page"])

    page =
      Catalog.list_courses_page(
        status: :published,
        public_only: true,
        search: search,
        price: price,
        page: page_number
      )

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:price, price)
     |> assign(:page, page)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: courses_path(search: search, price: socket.assigns.price))}
  end

  defp normalize_price(price) when price in ["free", "paid"], do: price
  defp normalize_price(_price), do: "all"

  defp courses_path(opts) do
    params =
      %{
        search: Keyword.get(opts, :search, ""),
        price: Keyword.get(opts, :price, "all"),
        page: Keyword.get(opts, :page, 1)
      }
      |> Enum.reject(fn
        {:page, 1} -> true
        {:price, "all"} -> true
        {_key, value} -> value in [nil, ""]
      end)

    ~p"/courses?#{params}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-soft text-dark">
      <.home_header current_user={@current_user} />

      <main>
        <section class="bg-white py-20 lg:py-28">
          <div class="mx-auto max-w-container px-5 lg:px-8">
            <div class="mx-auto max-w-2xl text-center">
              <h1 class="text-4xl font-semibold leading-[1.1] text-dark sm:text-5xl lg:text-6xl">
                Explore all GS1 courses
              </h1>
              <p class="mt-6 text-lg text-body">
                Compare course outcomes, duration, lessons and price before opening the full course
                page.
              </p>

              <form
                phx-change="search"
                class="mx-auto mt-8 flex max-w-md items-center gap-2 rounded-full border border-black/10 bg-white px-5 py-3 shadow-sm focus-within:border-dark"
              >
                <svg
                  class="h-5 w-5 shrink-0 text-muted"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <circle cx="11" cy="11" r="7" /><line x1="21" y1="21" x2="16.65" y2="16.65" />
                </svg>
                <input
                  type="search"
                  name="search"
                  value={@search}
                  placeholder="Search courses…"
                  phx-debounce="300"
                  class="w-full border-0 bg-transparent p-0 text-sm text-dark placeholder:text-muted focus:outline-none focus:ring-0"
                />
              </form>

              <div class="mt-6 flex justify-center">
                <.catalog_filters
                  price={@price}
                  price_href={fn value -> courses_path(search: @search, price: value) end}
                />
              </div>

              <p class="mt-4 text-sm text-muted">
                {@page.total_count} {ngettext("course", "courses", @page.total_count)}
              </p>
            </div>

            <.paginated_table
              page={@page.page}
              total_pages={@page.total_pages}
              path_fn={&courses_path(search: @search, price: @price, page: &1)}
            >
              <div
                :if={@page.entries != []}
                id="published-courses"
                class="mt-14 grid gap-7 md:grid-cols-2 lg:grid-cols-3"
              >
                <WasomiWeb.HomeComponents.course_card :for={course <- @page.entries} course={course} />
              </div>

              <div
                :if={@page.entries == [] and @search != ""}
                id="empty-catalog"
                class="mx-auto mt-14 max-w-xl rounded-3xl border border-black/5 bg-white p-10 text-center"
              >
                <.icon name="hero-magnifying-glass" class="h-10 w-10 text-primary" />
                <h2 class="mt-4 text-xl font-semibold">No courses match "{@search}".</h2>
                <p class="mt-2 text-body">Try a different search, or explore all courses.</p>
              </div>

              <div
                :if={@page.entries == [] and @search == ""}
                id="empty-catalog"
                class="mx-auto mt-14 max-w-xl rounded-3xl border border-black/5 bg-white p-10 text-center"
              >
                <.icon name="hero-academic-cap" class="h-10 w-10 text-primary" />
                <h2 class="mt-4 text-xl font-semibold">New courses are on the way.</h2>
                <p class="mt-2 text-body">Check back soon for Wasomi's first learning experience.</p>
              </div>
            </.paginated_table>
          </div>
        </section>
      </main>
    </div>
    """
  end
end
