defmodule WasomiWeb.LearnerProfileLive do
  @moduledoc """
  Public learner profile page.

  A profile only resolves when the learner has explicitly enabled public
  visibility. It never renders private contact details such as email or phone,
  and certificate links go through the existing public GDTI verification page
  rather than signed PDF download URLs.
  """

  use WasomiWeb, :live_view

  import WasomiWeb.HomeComponents, only: [footer: 1]

  alias Wasomi.{Accounts, Certificates}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    socket =
      assign(socket, :authed_learner?, match?(%{role: :learner}, socket.assigns[:current_user]))

    case Accounts.get_public_profile_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> assign(:page_title, "Learner profile")
         |> assign(:profile, nil)
         |> assign(:certificates, [])}

      user ->
        {:ok,
         socket
         |> assign(:page_title, "#{user.name} — Wasomi Learner")
         |> assign(:profile, Accounts.public_profile_view(user))
         |> assign(:certificates, Certificates.list_public_for_user(user))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.student_layout :if={@authed_learner?} active={nil} current_user={@current_user}>
      <div class="mx-auto max-w-5xl px-5 py-10 lg:px-8 lg:py-12">
        <.profile_body profile={@profile} certificates={@certificates} />
      </div>
    </.student_layout>

    <div :if={!@authed_learner?} class="min-h-screen bg-surface">
      <header class="border-b border-black/5 bg-white">
        <div class="mx-auto flex max-w-5xl items-center justify-between px-5 py-6">
          <.link navigate={~p"/"} class="inline-flex items-center">
            <img src={~p"/images/logo.png"} alt="Wasomi" class="h-8 w-auto" />
          </.link>
          <.link
            navigate={~p"/courses"}
            class="text-sm font-semibold text-primary transition hover:text-ink"
          >
            Explore courses
          </.link>
        </div>
      </header>

      <main class="mx-auto max-w-5xl px-5 py-10 lg:py-14">
        <.profile_body profile={@profile} certificates={@certificates} />
      </main>

      <.footer />
    </div>
    """
  end

  attr :profile, :map, required: true
  attr :certificates, :list, required: true

  defp profile_body(assigns) do
    ~H"""
    <%= if @profile do %>
      <section class="overflow-hidden rounded-3xl border border-black/5 bg-white shadow-card">
        <div class="grid gap-8 p-6 sm:p-8 lg:grid-cols-[220px_minmax(0,1fr)] lg:p-10">
          <div>
            <div class="grid h-32 w-32 place-items-center overflow-hidden rounded-full bg-mint text-4xl font-semibold uppercase text-primary ring-8 ring-mint/50">
              <%= if @profile.avatar_key do %>
                <img src={@profile.avatar_key} alt="" class="h-full w-full object-cover" />
              <% else %>
                {profile_initial(@profile)}
              <% end %>
            </div>

            <.link
              :if={@profile.linkedin_url}
              href={@profile.linkedin_url}
              target="_blank"
              rel="noopener noreferrer"
              aria-label="View LinkedIn profile (opens in a new tab)"
              class="mt-6 inline-flex items-center gap-2 rounded-full bg-dark px-4 py-2 text-sm font-semibold text-white transition hover:bg-primary"
            >
              <svg viewBox="0 0 24 24" fill="currentColor" class="h-4 w-4" aria-hidden="true">
                <path d="M20.45 20.45h-3.56v-5.57c0-1.33-.03-3.04-1.85-3.04-1.85 0-2.14 1.45-2.14 2.94v5.67H9.35V9h3.42v1.56h.05c.47-.9 1.64-1.85 3.37-1.85 3.6 0 4.27 2.37 4.27 5.46v6.28zM5.34 7.43a2.07 2.07 0 1 1 0-4.14 2.07 2.07 0 0 1 0 4.14zM7.12 20.45H3.56V9h3.56v11.45zM22.22 0H1.77C.79 0 0 .77 0 1.72v20.56C0 23.23.79 24 1.77 24h20.45c.98 0 1.78-.77 1.78-1.72V1.72C24 .77 23.2 0 22.22 0z" />
              </svg>
              View LinkedIn profile
            </.link>
          </div>

          <div>
            <p class="text-sm font-semibold uppercase tracking-wider text-primary">
              Wasomi Learner
            </p>
            <h1 class="mt-2 text-3xl font-semibold leading-tight text-ink sm:text-4xl">
              {@profile.name}
            </h1>
            <p :if={@profile.headline} class="mt-3 text-lg font-medium text-ink">
              {@profile.headline}
            </p>
            <p :if={@profile.bio} class="mt-4 max-w-2xl text-body">
              {@profile.bio}
            </p>

            <dl
              :if={@profile.industry || @profile.country}
              class="mt-8 grid gap-5 border-t border-black/5 pt-6 sm:grid-cols-2"
            >
              <div :if={@profile.industry}>
                <dt class="text-xs font-semibold uppercase tracking-wider text-muted">
                  Industry
                </dt>
                <dd class="mt-1 font-semibold text-ink">{@profile.industry}</dd>
              </div>
              <div :if={@profile.country}>
                <dt class="text-xs font-semibold uppercase tracking-wider text-muted">
                  Country
                </dt>
                <dd class="mt-1 font-semibold text-ink">{@profile.country}</dd>
              </div>
            </dl>
          </div>
        </div>
      </section>

      <section
        :if={@certificates != []}
        class="mt-8 rounded-3xl border border-black/5 bg-white p-6 shadow-card sm:p-8"
      >
        <div class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <p class="text-sm font-semibold uppercase tracking-wider text-primary">
              Certificates
            </p>
            <h2 class="mt-2 text-2xl font-semibold text-ink">Verified achievements</h2>
          </div>
          <span class="text-sm text-muted">
            {length(@certificates)} public
          </span>
        </div>

        <div class="mt-6 grid gap-4 sm:grid-cols-2">
          <article
            :for={certificate <- @certificates}
            class="rounded-2xl border border-black/5 bg-surface p-5"
          >
            <p class="text-xs font-semibold uppercase tracking-wider text-muted">
              Course certificate
            </p>
            <h3 class="mt-2 font-semibold text-ink">{certificate.course.title}</h3>
            <p class="mt-1 text-sm text-body">
              Issued {Calendar.strftime(certificate.issued_at, "%B %-d, %Y")}
            </p>
            <.link
              navigate={~p"/certificates/253/#{certificate.gdti}"}
              class="mt-4 inline-flex items-center gap-2 text-sm font-semibold text-primary transition hover:text-ink"
            >
              Verify certificate <.icon name="hero-arrow-up-right" class="h-4 w-4" />
            </.link>
          </article>
        </div>
      </section>
    <% else %>
      <section class="mx-auto max-w-xl rounded-3xl border border-black/5 bg-white p-8 text-center shadow-card sm:p-12">
        <div class="mx-auto grid h-16 w-16 place-items-center rounded-full bg-mint text-primary">
          <.icon name="hero-user-circle" class="h-9 w-9" />
        </div>
        <h1 class="mt-5 text-2xl font-semibold text-ink">Profile unavailable</h1>
        <p class="mt-2 text-body">
          This learner profile is private, unpublished, or the link is no longer active.
        </p>
        <.link
          navigate={~p"/courses"}
          class="mt-6 inline-flex rounded-full bg-ink px-6 py-3 font-semibold text-white transition hover:bg-primary"
        >
          Explore courses
        </.link>
      </section>
    <% end %>
    """
  end

  defp profile_initial(profile), do: profile.name |> to_string() |> String.first()
end
