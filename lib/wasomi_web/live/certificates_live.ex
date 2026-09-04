defmodule WasomiWeb.CertificatesLive do
  use WasomiWeb, :live_view

  alias Wasomi.Certificates

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Certificates.subscribe(socket.assigns.current_user)
    end

    {:ok,
     socket
     |> assign(:page_title, "Certificates")
     |> load_certificates()}
  end

  @impl true
  def handle_info({:certificate_ready, _certificate}, socket) do
    {:noreply, load_certificates(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("retry-certificate", %{"course-id" => course_id}, socket) do
    Certificates.ensure_issued(
      socket.assigns.current_user.id,
      String.to_integer(course_id)
    )

    {:noreply,
     socket
     |> put_flash(:info, "We're preparing your certificate — this can take a moment.")
     |> load_certificates()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.student_layout active={:certificates} current_user={@current_user}>
      <div class="w-full px-5 py-8 lg:px-8">
        <.learner_page_header eyebrow="Achievements" title="Your certificates.">
          <:actions :if={@certificates != []}>{length(@certificates)} earned</:actions>
        </.learner_page_header>

        <div
          :if={@certificates != [] or @pending != []}
          id="certificates-list"
          class="mt-8 grid gap-5 md:grid-cols-2"
        >
          <article
            :for={certificate <- @certificates}
            id={"certificate-#{certificate.id}"}
            class="flex items-center justify-between gap-4 rounded-3xl border border-black/5 bg-white p-6 shadow-card"
          >
            <div class="min-w-0">
              <p class="text-xs font-semibold uppercase tracking-wider text-primary">
                {certificate_type(certificate)}
              </p>
              <h3 class="mt-1 truncate font-medium text-ink">{certificate_title(certificate)}</h3>
              <p class="mt-1 text-xs text-muted">{certificate.gdti}</p>
            </div>
            <.link
              href={~p"/certificates/#{certificate.id}/download"}
              class="inline-flex shrink-0 items-center gap-2 rounded-full bg-ink px-4 py-2 text-sm font-medium text-white transition hover:bg-primary"
            >
              <.icon name="hero-arrow-down-tray" class="h-4 w-4" /> Download
            </.link>
          </article>

          <%!-- Course finished, certificate not written yet — acknowledge it and
          offer a manual retry rather than showing nothing. --%>
          <article
            :for={course <- @pending}
            id={"certificate-pending-#{course.id}"}
            class="flex items-center justify-between gap-4 rounded-3xl border border-dashed border-primary/30 bg-mint/40 p-6"
          >
            <div class="min-w-0">
              <p class="text-xs font-semibold uppercase tracking-wider text-primary">
                Course certificate
              </p>
              <h3 class="mt-1 truncate font-medium text-ink">{course.title}</h3>
              <p class="mt-1 inline-flex items-center gap-1.5 text-xs text-muted">
                <.icon name="hero-arrow-path" class="h-3.5 w-3.5 animate-spin" /> Preparing…
              </p>
            </div>
            <button
              type="button"
              phx-click="retry-certificate"
              phx-value-course-id={course.id}
              class="inline-flex shrink-0 items-center gap-2 rounded-full border border-primary/40 px-4 py-2 text-sm font-medium text-primary transition hover:bg-primary hover:text-white"
            >
              <.icon name="hero-arrow-path" class="h-4 w-4" /> Retry
            </button>
          </article>
        </div>

        <div
          :if={@certificates == [] and @pending == []}
          id="certificates-empty"
          class="mt-8 rounded-3xl border border-black/5 bg-white p-8 text-center shadow-card sm:p-12"
        >
          <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
            <.icon name="hero-trophy" class="h-7 w-7" />
          </span>
          <h3 class="mt-5 text-xl font-semibold text-ink">No certificates yet.</h3>
          <p class="mx-auto mt-2 max-w-lg text-body">
            Certificates will appear here as you complete modules and courses.
          </p>
          <.link
            navigate={~p"/courses-taken"}
            class="mt-6 inline-flex rounded-full bg-ink px-6 py-3 font-medium text-white transition hover:bg-primary"
          >
            Go to my courses
          </.link>
        </div>
      </div>
    </.student_layout>
    """
  end

  defp load_certificates(socket) do
    user = socket.assigns.current_user

    socket
    |> assign(:certificates, Certificates.list_for_user(user))
    |> assign(:pending, Certificates.pending_certificate_courses(user))
  end

  defp certificate_type(%{type: :course}), do: "Course certificate"
  defp certificate_title(%{type: :course, course: course}), do: course.title
end
