defmodule WasomiWeb.CatalogLive.Portal do
  @moduledoc """
  Authenticated learner-facing catalog.

  Same published-course listing as `WasomiWeb.CatalogLive.Index`, reusing
  `Wasomi.Catalog` for data, but wrapped in the student portal sidebar
  instead of the public marketing chrome. It's a discovery surface: courses
  the learner already has show an "Enrolled"/"Completed" badge and link
  straight into the player, and a filter can hide them entirely.
  """
  use WasomiWeb, :live_view

  alias Wasomi.{Catalog, Enrollments, Learning}
  alias Wasomi.Paginate

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Browse catalog")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    user = socket.assigns.current_user
    search = params["search"] || ""
    price = normalize_price(params["price"])
    hide_enrolled = params["hide_enrolled"] == "1"
    page_number = Paginate.parse_page(params["page"])

    exclude_ids = if hide_enrolled, do: Enrollments.active_course_ids(user), else: []

    page =
      Catalog.list_courses_page(
        status: :published,
        search: search,
        price: price,
        exclude_ids: exclude_ids,
        page: page_number
      )

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:price, price)
     |> assign(:hide_enrolled, hide_enrolled)
     |> assign(:page, page)
     |> assign(:cards, Enum.map(page.entries, &build_card(user, &1)))}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: catalog_path(socket.assigns, search: search))}
  end

  defp normalize_price(price) when price in ["free", "paid"], do: price
  defp normalize_price(_price), do: "all"

  # Builds a `/catalog` patch path from the current filter assigns plus any
  # overrides (`search:`, `price:`, `hide_enrolled:`, `page:`). Every state
  # change resets to page 1.
  defp catalog_path(assigns, overrides) do
    %{
      search: assigns.search,
      price: assigns.price,
      hide_enrolled: if(assigns.hide_enrolled, do: "1", else: nil),
      page: 1
    }
    |> Map.merge(Map.new(overrides))
    |> Enum.reject(fn
      {:page, 1} -> true
      {:price, "all"} -> true
      {_key, value} -> value in [nil, ""]
    end)
    |> build_catalog_url()
  end

  defp build_catalog_url(params), do: ~p"/catalog?#{params}"

  defp build_card(user, course) do
    if Enrollments.can_access_course?(user, course) do
      badge =
        if Learning.course_progress(user, course).complete?, do: "Completed", else: "Enrolled"

      {:enrolled, %{course: course, badge: badge}}
    else
      {:available, course}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.student_layout active={:browse} current_user={@current_user}>
      <div class="w-full px-5 py-8 lg:px-8">
        <.learner_page_header eyebrow="Browse catalog" title="Explore all GS1 courses.">
          <:actions>
            {@page.total_count} {ngettext("course", "courses", @page.total_count)}
          </:actions>
        </.learner_page_header>

        <div class="mt-6 flex flex-wrap items-center gap-3">
          <form
            phx-change="search"
            class="flex w-full max-w-xs items-center gap-2 rounded-full border border-black/10 bg-white px-5 py-3 shadow-sm focus-within:border-primary"
          >
            <.icon name="hero-magnifying-glass" class="h-5 w-5 shrink-0 text-muted" />
            <input
              type="search"
              name="search"
              value={@search}
              placeholder="Search courses…"
              phx-debounce="300"
              class="w-full border-0 bg-transparent p-0 text-sm text-ink placeholder:text-muted focus:outline-none focus:ring-0"
            />
          </form>

          <WasomiWeb.HomeComponents.catalog_filters
            price={@price}
            price_href={fn value -> catalog_path(assigns, price: value) end}
            hide_enrolled={@hide_enrolled}
            toggle_enrolled_href={
              catalog_path(assigns, hide_enrolled: if(@hide_enrolled, do: nil, else: "1"))
            }
          />
        </div>

        <.paginated_table
          page={@page.page}
          total_pages={@page.total_pages}
          path_fn={&catalog_path(assigns, page: &1)}
        >
          <div
            :if={@cards != []}
            id="portal-catalog-courses"
            class="mt-8 grid gap-7 sm:grid-cols-2 xl:grid-cols-3"
          >
            <%= for {state, card} <- @cards do %>
              <WasomiWeb.HomeComponents.course_card
                :if={state == :enrolled}
                course={card.course}
                status_badge={card.badge}
                href={~p"/learn/courses/#{card.course.slug}"}
              />
              <WasomiWeb.HomeComponents.course_card :if={state == :available} course={card} />
            <% end %>
          </div>

          <div
            :if={@cards == [] and (@search != "" or @price != "all" or @hide_enrolled)}
            id="portal-catalog-empty"
            class="mt-14 rounded-3xl border border-black/5 bg-white p-10 text-center"
          >
            <.icon name="hero-magnifying-glass" class="h-10 w-10 text-primary" />
            <h2 class="mt-4 text-xl font-semibold">No courses match your filters.</h2>
            <p class="mt-2 text-body">Try clearing a filter or searching for something else.</p>
          </div>

          <div
            :if={@cards == [] and @search == "" and @price == "all" and not @hide_enrolled}
            id="portal-catalog-empty"
            class="mt-14 rounded-3xl border border-black/5 bg-white p-10 text-center"
          >
            <.icon name="hero-academic-cap" class="h-10 w-10 text-primary" />
            <h2 class="mt-4 text-xl font-semibold">New courses are on the way.</h2>
            <p class="mt-2 text-body">Check back soon for Wasomi's first learning experience.</p>
          </div>
        </.paginated_table>
      </div>
    </.student_layout>
    """
  end
end
