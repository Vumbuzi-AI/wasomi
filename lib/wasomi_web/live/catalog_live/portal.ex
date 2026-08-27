defmodule WasomiWeb.CatalogLive.Portal do
  @moduledoc """
  Authenticated learner-facing catalog.

  Same published-course listing as `WasomiWeb.CatalogLive.Index`, reusing
  `Wasomi.Catalog` for data, but wrapped in the student portal sidebar
  instead of the public marketing chrome. Each card reflects the viewing
  learner's own enrollment/progress state, so "Browse catalog" from the
  sidebar feels like part of the app rather than a jump out to the public
  site.
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
    search = params["search"] || ""
    page_number = Paginate.parse_page(params["page"])

    page =
      Catalog.list_courses_page(status: :published, search: search, page: page_number)

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:page, page)
     |> assign(:cards, Enum.map(page.entries, &build_card(socket.assigns.current_user, &1)))}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: courses_path(search, 1))}
  end

  defp courses_path(search, page) do
    params =
      %{search: search, page: page}
      |> Enum.reject(fn
        {:page, 1} -> true
        {_key, value} -> value in [nil, ""]
      end)

    ~p"/catalog?#{params}"
  end

  defp build_card(user, course) do
    if Enrollments.can_access_course?(user, course) do
      progress = Learning.course_progress(user, course)

      {:enrolled,
       %{
         course: course,
         progress: progress,
         resume_lecture: resume_lecture(course, progress.progress),
         started?: map_size(progress.progress) > 0
       }}
    else
      {:available, course}
    end
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

  @impl true
  def render(assigns) do
    ~H"""
    <.student_layout active={:browse} current_user={@current_user}>
      <div class="w-full px-5 py-8 lg:px-8">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p class="text-sm font-semibold uppercase tracking-wider text-primary">
              Browse catalog
            </p>
            <h1 class="mt-2 text-3xl font-semibold text-ink">Explore all GS1 courses.</h1>
          </div>
          <span class="text-sm text-muted">
            {@page.total_count} {ngettext("course", "courses", @page.total_count)}
          </span>
        </div>

        <form
          phx-change="search"
          class="mt-6 flex max-w-md items-center gap-2 rounded-full border border-black/10 bg-white px-5 py-3 shadow-sm focus-within:border-primary"
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

        <.paginated_table
          page={@page.page}
          total_pages={@page.total_pages}
          path_fn={&courses_path(@search, &1)}
        >
          <div
            :if={@cards != []}
            id="portal-catalog-courses"
            class="mt-8 grid gap-7 sm:grid-cols-2 xl:grid-cols-3"
          >
            <%= for {state, card} <- @cards do %>
              <.course_card
                :if={state == :enrolled}
                card={card}
                id={"portal-catalog-course-#{card.course.id}"}
                progress_id={"portal-catalog-progress-#{card.course.id}"}
              />
              <WasomiWeb.HomeComponents.course_card :if={state == :available} course={card} />
            <% end %>
          </div>

          <div
            :if={@cards == [] and @search != ""}
            id="portal-catalog-empty"
            class="mt-14 rounded-3xl border border-black/5 bg-white p-10 text-center"
          >
            <.icon name="hero-magnifying-glass" class="h-10 w-10 text-primary" />
            <h2 class="mt-4 text-xl font-semibold">No courses match "{@search}".</h2>
            <p class="mt-2 text-body">Try a different search, or explore all courses.</p>
          </div>

          <div
            :if={@cards == [] and @search == ""}
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
