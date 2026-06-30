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
     |> assign(:current_user, current_user(session))
     |> assign(:courses, Catalog.list_published_courses())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen  bg-slate-50 text-slate-900">
      <.home_header current_user={@current_user} />
      <main>
        <.hero />
        <.top_courses_section courses={@courses} />
        <.why_choose_us />
        <.popular_courses courses={@courses} />
        <.digital_skills />
        <.mentors />
        <.testimonials />
        <.faqs />
        <.blog />
        <.cta />
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
