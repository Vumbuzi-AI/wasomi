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
  def render(assigns) do
    ~H"""
    <.student_layout active={:certificates} current_user={@current_user}>
      <div class="mx-auto max-w-container px-5 py-10 lg:px-10 lg:py-12">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p class="text-sm font-semibold uppercase tracking-wider text-primary">Achievements</p>
            <h1 class="mt-2 text-3xl font-semibold text-dark">Your certificates.</h1>
          </div>
          <span :if={@certificates != []} class="text-sm text-muted">
            {length(@certificates)} earned
          </span>
        </div>

        <div :if={@certificates != []} id="certificates-list" class="mt-8 grid gap-5 md:grid-cols-2">
          <article
            :for={certificate <- @certificates}
            id={"certificate-#{certificate.id}"}
            class="flex items-center justify-between gap-4 rounded-3xl border border-black/5 bg-white p-6"
          >
            <div class="min-w-0">
              <p class="text-xs font-semibold uppercase tracking-wider text-primary">
                {certificate_type(certificate)}
              </p>
              <h3 class="mt-1 truncate font-medium text-dark">{certificate_title(certificate)}</h3>
              <p class="mt-1 text-xs text-muted">{certificate.serial_number}</p>
            </div>
            <.link
              href={~p"/certificates/#{certificate.id}/download"}
              class="inline-flex shrink-0 items-center gap-2 rounded-full bg-dark px-4 py-2 text-sm font-medium text-white transition hover:bg-primary"
            >
              <.icon name="hero-arrow-down-tray" class="h-4 w-4" /> Download
            </.link>
          </article>
        </div>

        <div
          :if={@certificates == []}
          id="certificates-empty"
          class="mt-8 rounded-3xl border border-black/5 bg-white p-8 text-center sm:p-12"
        >
          <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
            <.icon name="hero-trophy" class="h-7 w-7" />
          </span>
          <h3 class="mt-5 text-xl font-semibold text-dark">No certificates yet.</h3>
          <p class="mx-auto mt-2 max-w-lg text-body">
            Certificates will appear here as you complete modules and courses.
          </p>
          <.link
            navigate={~p"/courses-taken"}
            class="mt-6 inline-flex rounded-full bg-dark px-6 py-3 font-medium text-white transition hover:bg-primary"
          >
            Go to my courses
          </.link>
        </div>
      </div>
    </.student_layout>
    """
  end

  defp load_certificates(socket) do
    assign(socket, :certificates, Certificates.list_for_user(socket.assigns.current_user))
  end

  defp certificate_type(%{type: :module}), do: "Module certificate"
  defp certificate_type(%{type: :course}), do: "Course certificate"
  defp certificate_title(%{type: :module, module: module}), do: module.title
  defp certificate_title(%{type: :course, course: course}), do: course.title
end
