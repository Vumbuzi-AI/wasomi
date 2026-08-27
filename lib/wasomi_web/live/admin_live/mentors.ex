defmodule WasomiWeb.AdminLive.Mentors do
  use WasomiWeb, :live_view

  alias Wasomi.Mentors
  alias Wasomi.Mentors.Mentor
  alias WasomiWeb.MentorLive.FormComponent

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Mentors")
     |> assign(:deleting_mentor, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> apply_action(socket.assigns.live_action, params)
     |> assign(:search, params["q"] || "")
     |> load_mentors()}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, mentor: nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:mentor, %Mentor{position: Mentors.count_mentors() + 1, is_active: true})
    |> assign(:form_title, "New mentor")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:mentor, Mentors.get_mentor!(id))
    |> assign(:form_title, "Edit mentor")
  end

  @impl true
  def handle_info({FormComponent, {:saved, _mentor}}, socket) do
    {:noreply, load_mentors(socket)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, push_patch(socket, to: mentors_path(query))}
  end

  def handle_event("confirm_delete_mentor", %{"id" => id}, socket) do
    {:noreply, assign(socket, :deleting_mentor, Mentors.get_mentor!(id))}
  end

  def handle_event("cancel_delete_mentor", _params, socket) do
    {:noreply, assign(socket, :deleting_mentor, nil)}
  end

  def handle_event("delete_mentor", %{"id" => id}, socket) do
    {:ok, _mentor} = Mentors.delete_mentor(Mentors.get_mentor!(id))

    {:noreply,
     socket
     |> put_flash(:info, "Mentor removed.")
     |> assign(:deleting_mentor, nil)
     |> load_mentors()}
  end

  defp mentors_path(search) do
    params = if search in [nil, ""], do: %{}, else: %{q: search}
    ~p"/admin/mentors?#{params}"
  end

  defp load_mentors(socket) do
    mentors = Mentors.list_mentors(search: socket.assigns.search)

    socket
    |> assign(:mentors, mentors)
    |> assign(:total_count, Mentors.count_mentors())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:mentors} current_user={@current_user}>
      <div class="w-full space-y-5 px-5 py-8 lg:px-8">
        <.page_header title="Mentors">
          <:subtitle>Manage the mentors featured on the public homepage.</:subtitle>
          <:actions>
            <.search_input value={@search} placeholder="Search name or role" />
            <.link
              patch={~p"/admin/mentors/new"}
              class="group flex h-11 items-center gap-2 rounded-full bg-ink py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
            >
              New mentor
              <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover:bg-ink">
                <.icon name="hero-plus-mini" class="h-4 w-4" />
              </span>
            </.link>
          </:actions>
        </.page_header>

        <div class="rounded-[2rem] border border-black/5 bg-white p-6 shadow-card lg:p-8">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div>
              <h2 class="text-xl font-semibold text-ink">Mentor roster</h2>
              <p class="mt-1 text-sm text-body">
                Shown in display order on the "Learn from the Best" homepage section.
              </p>
            </div>
            <span class="rounded-full border border-primary/30 bg-mint px-3 py-1 text-xs font-semibold text-primary">
              {@total_count} {ngettext("mentor", "mentors", @total_count)}
            </span>
          </div>

          <div :if={@mentors != []} class="mt-6 grid gap-6 sm:grid-cols-2 xl:grid-cols-3">
            <article
              :for={mentor <- @mentors}
              id={"mentor-row-#{mentor.id}"}
              class="group relative flex flex-col overflow-hidden rounded-3xl border border-black/5 bg-white shadow-card transition hover:-translate-y-1 hover:shadow-card-hover"
            >
              <div class="relative aspect-[4/3] overflow-hidden bg-neutral-100">
                <img
                  :if={mentor.photo_key}
                  src={mentor.photo_key}
                  alt={mentor.name}
                  class="h-full w-full object-cover"
                />
                <div
                  :if={!mentor.photo_key}
                  class="flex h-full w-full items-center justify-center text-muted"
                >
                  <.icon name="hero-user" class="h-10 w-10" />
                </div>
                <span class="absolute left-4 top-4 z-10">
                  <.status_badge status={if(mentor.is_active, do: :published, else: :draft)} />
                </span>
                <div class="absolute right-4 top-4 z-10 flex items-center gap-2">
                  <.link
                    patch={~p"/admin/mentors/#{mentor.id}/edit"}
                    class="grid h-9 w-9 place-items-center rounded-full bg-white/95 text-ink shadow-sm backdrop-blur transition hover:bg-white hover:text-primary"
                    title="Edit mentor"
                  >
                    <.icon name="hero-pencil-square" class="h-4 w-4" />
                  </.link>
                  <button
                    type="button"
                    phx-click={JS.push("confirm_delete_mentor", value: %{id: mentor.id})}
                    class="grid h-9 w-9 place-items-center rounded-full bg-white/95 text-ink shadow-sm backdrop-blur transition hover:bg-white hover:text-red-500"
                    title="Delete mentor"
                  >
                    <.icon name="hero-trash" class="h-4 w-4" />
                  </button>
                </div>
              </div>

              <div class="flex flex-1 flex-col p-6">
                <h3 class="text-lg font-semibold leading-snug text-ink">{mentor.name}</h3>
                <p class="mt-1 text-sm text-body">{mentor.role}</p>
                <p class="mt-4 text-xs text-muted">Display order: {mentor.position}</p>
              </div>
            </article>
          </div>

          <div
            :if={@mentors == [] and @total_count == 0}
            class="mt-6 rounded-3xl border border-black/5 bg-surface p-12 text-center"
          >
            <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
              <.icon name="hero-user-group" class="h-7 w-7" />
            </span>
            <h3 class="mt-5 text-xl font-semibold text-ink">No mentors yet</h3>
            <p class="mx-auto mt-2 max-w-md text-body">
              Add your first mentor to feature them on the homepage.
            </p>
            <.link
              patch={~p"/admin/mentors/new"}
              class="mt-6 inline-flex rounded-full bg-ink px-6 py-3 font-medium text-white transition hover:bg-primary"
            >
              New mentor
            </.link>
          </div>

          <div
            :if={@mentors == [] and @total_count > 0}
            class="mt-6 rounded-3xl border border-black/5 bg-surface p-12 text-center"
          >
            <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
              <.icon name="hero-magnifying-glass" class="h-7 w-7" />
            </span>
            <h3 class="mt-5 text-xl font-semibold text-ink">No matching mentors</h3>
            <p class="mx-auto mt-2 max-w-md text-body">Try a different search term.</p>
            <.link
              patch={~p"/admin/mentors"}
              class="mt-6 inline-flex rounded-full border border-black/10 px-6 py-3 font-medium text-ink transition hover:border-primary hover:text-primary"
            >
              Clear search
            </.link>
          </div>
        </div>
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="mentor-modal"
        show
        on_cancel={JS.patch(~p"/admin/mentors")}
      >
        <.live_component
          module={FormComponent}
          id={@mentor.id || :new}
          title={@form_title}
          action={@live_action}
          mentor={@mentor}
          patch={fn _mentor -> ~p"/admin/mentors" end}
        />
      </.modal>

      <.confirm_modal
        :if={@deleting_mentor}
        id="delete-mentor-modal"
        title={"Remove \"#{@deleting_mentor.name}\"?"}
        confirm_label="Remove"
        confirm={JS.push("delete_mentor", value: %{id: @deleting_mentor.id})}
        cancel={JS.push("cancel_delete_mentor")}
      >
        This removes the mentor from the homepage. This action cannot be undone.
      </.confirm_modal>
    </.admin_layout>
    """
  end
end
