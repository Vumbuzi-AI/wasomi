defmodule WasomiWeb.HomeLive do
  use WasomiWeb, :live_view

  import WasomiWeb.HomeComponents
  alias Wasomi.Accounts
  alias Wasomi.Catalog

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Wasomi Business Institute")
     |> assign(:page_title_suffix, "")
     |> assign(:current_user, current_user(session))
     |> assign(:courses, Catalog.list_published_courses())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen  bg-slate-50 text-slate-900">
      <.announcement_bar />
      <.home_header current_user={@current_user} />
      <main>
        <.hero />
        <.about_wasomi />
        <.gs1_in_action />
        <.top_courses_section courses={@courses} />
        <.gs1_in_workplaces />
        <.how_it_works />
        <.mentors />
        <.certificates />
        <.faqs />
      </main>
      <.footer />
    </div>
    """
  end

  defp current_user(%{"user_token" => user_token}) do
    Accounts.get_user_by_session_token(user_token)
  end

  defp current_user(_session), do: nil
end
