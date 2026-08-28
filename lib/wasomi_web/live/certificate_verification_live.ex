defmodule WasomiWeb.CertificateVerificationLive do
  @moduledoc """
  Public, unauthenticated page a GDTI Digital Link QR/URL resolves to:
  `/certificates/253/:gdti`. Confirms a certificate is genuine without
  exposing anything sensitive — no email, no download link to the PDF
  itself, just enough to confirm "yes, this certificate is real" (learner
  name, what it's for, when it was issued). Deliberately never offers a
  download of the actual certificate file: anyone holding the GDTI printed
  on/encoded in a certificate could otherwise pull the PDF on demand,
  which is exactly the leak this page exists to prevent.

  An unrecognized GDTI (mistyped, tampered with, or simply fake) is an
  expected, everyday outcome here, not an error — so it renders its own
  "not verified" state, with the same visual weight as a real verification,
  on a normal 200 response rather than a 404/500 page.
  """

  use WasomiWeb, :live_view

  import WasomiWeb.HomeComponents

  alias Wasomi.Certificates
  alias Wasomi.Certificates.VerificationQR

  @impl true
  def mount(%{"gdti" => gdti}, _session, socket) do
    result = Certificates.verify_gdti(gdti)

    {:ok,
     socket
     |> assign(:gdti, gdti)
     |> assign(:result, result)
     |> assign_share_meta(result)}
  end

  # A crawler (LinkedIn, Slack, WhatsApp, ...) fetches these to build the
  # link-preview card when this URL gets shared anywhere — most usefully,
  # right where it's headed most often: the "Show credential" link on a
  # learner's LinkedIn certification entry (see
  # Wasomi.Certificates.linkedin_add_to_profile_url/1).
  #
  # `meta_image` deliberately isn't the certificate PDF/an image of it —
  # this page's whole design is to never expose that file to an outside
  # visitor (see moduledoc). It's the Wasomi/GS1 Kenya lockup instead (the
  # same pairing already in this page's own footer), sized to the standard
  # 1200x630 share-card ratio — answers "who is this from" at a glance,
  # which is what a verification card's image needs to do.
  #
  # `canonical_url` and `meta_robots` only get set here, on a genuine
  # match — an unrecognized/mistyped/attacker-guessed GDTI shouldn't get
  # its own indexable canonical page, and echoing that raw input back into
  # the response at all (even properly escaped) isn't something a "not
  # verified" page needs to do.
  defp assign_share_meta(socket, {:ok, certificate}) do
    socket
    |> assign(:meta_robots, "index, follow")
    |> assign(:canonical_url, VerificationQR.verification_url(certificate.gdti))
    |> assign(
      :page_title,
      "#{certificate.user.name} · #{certificate.course.title} — Verified Certificate"
    )
    |> assign(
      :meta_description,
      "Verified credential issued by GS1 Kenya and Wasomi Business Institute on " <>
        Calendar.strftime(certificate.issued_at, "%B %-d, %Y") <> "."
    )
    |> assign(:meta_image, url(~p"/images/og-certificate.png"))
    |> assign(:meta_image_alt, "Wasomi and GS1 Kenya")
  end

  defp assign_share_meta(socket, {:error, :not_found}) do
    assign(socket, :page_title, "Certificate Verification")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-surface">
      <main class="mx-auto max-w-2xl px-4 pb-20 pt-10 sm:pt-16">
        <div class="overflow-hidden rounded-3xl border border-black/5 bg-white shadow-card">
          <div class="p-8 sm:p-12">
            <div :if={match?({:ok, _}, @result)} class="text-center">
              <div class="mx-auto flex h-20 w-20 items-center justify-center rounded-full bg-emerald-50 ring-8 ring-emerald-50/60">
                <.icon name="hero-check-badge" class="h-11 w-11 text-emerald-600" />
              </div>
              <h1 class="mt-5 text-2xl font-bold text-ink sm:text-3xl">
                Verified Wasomi Certificate
              </h1>
              <p class="mt-2 text-body">
                This credential is genuine and on record with GS1 Kenya and Wasomi Business
                Institute.
              </p>

              <dl class="mt-10 grid gap-6 border-t border-black/5 pt-8 text-left sm:grid-cols-2">
                <div>
                  <dt class="text-xs font-semibold uppercase tracking-wider text-muted">
                    Awarded to
                  </dt>
                  <dd class="mt-1 text-lg font-semibold text-ink">{learner_name(@result)}</dd>
                </div>
                <div>
                  <dt class="text-xs font-semibold uppercase tracking-wider text-muted">
                    {certificate_type(@result)}
                  </dt>
                  <dd class="mt-1 text-lg font-semibold text-ink">
                    {certificate_title(@result)}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs font-semibold uppercase tracking-wider text-muted">
                    Issued
                  </dt>
                  <dd class="mt-1 font-medium text-ink">{issued_on(@result)}</dd>
                </div>
                <div>
                  <dt class="text-xs font-semibold uppercase tracking-wider text-muted">
                    Issuing organization
                  </dt>
                  <dd class="mt-1 font-medium text-ink">GS1 Kenya · Wasomi Business Institute</dd>
                </div>
              </dl>

              <div class="mt-8 flex flex-col items-center justify-between gap-5 border-t border-black/5 pt-8 sm:flex-row">
                <.link
                  navigate={~p"/"}
                  class="inline-flex items-center justify-center gap-4 px-2 py-1"
                  aria-label="Wasomi and GS1 Kenya"
                >
                  <img src={~p"/images/logo.png"} alt="Wasomi" class="h-6 w-auto object-contain" />
                  <span class="h-6 w-px bg-black/10"></span>
                  <img
                    src={~p"/images/gs1ke-logo.png"}
                    alt="GS1 Kenya"
                    class="h-7 w-auto object-contain"
                  />
                </.link>

                <.link
                  :if={course_viewable?(@result)}
                  navigate={~p"/courses/#{course_slug(@result)}"}
                  class="inline-flex items-center justify-center gap-2 rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-ink"
                >
                  View course <.icon name="hero-arrow-up-right" class="h-4 w-4" />
                </.link>
              </div>
            </div>

            <div :if={match?({:error, :not_found}, @result)} class="text-center">
              <div class="mx-auto flex h-20 w-20 items-center justify-center rounded-full bg-orange-50 ring-8 ring-orange-50/60">
                <.icon name="hero-question-mark-circle" class="h-11 w-11 text-primary" />
              </div>
              <h1 class="mt-5 text-2xl font-bold text-ink sm:text-3xl">
                Certificate not found
              </h1>
              <p class="mx-auto mt-2 max-w-sm text-body">
                We couldn't match this verification code to a Wasomi certificate record. Check
                that the full link or certificate number was copied correctly.
              </p>
            </div>
          </div>

          <div
            :if={match?({:ok, _}, @result)}
            class="flex items-center justify-between gap-4 bg-ink px-8 py-4 sm:px-12"
          >
            <span class="text-sm font-medium text-white/90">Wasomi Certification Record</span>
            <span class="break-all font-mono text-xs text-white/60">Ref: {@gdti}</span>
          </div>
        </div>
      </main>

      <.footer />
    </div>
    """
  end

  defp learner_name({:ok, certificate}), do: certificate.user.name
  defp certificate_type({:ok, %{type: :course}}), do: "Course"
  defp certificate_title({:ok, %{type: :course, course: course}}), do: course.title
  defp issued_on({:ok, certificate}), do: Calendar.strftime(certificate.issued_at, "%B %-d, %Y")

  # Only link out to a course still actually reachable at its public URL —
  # a certificate can outlive the course being archived/unpublished later.
  defp course_viewable?({:ok, %{course: %{status: :published}}}), do: true
  defp course_viewable?(_result), do: false

  defp course_slug({:ok, certificate}), do: certificate.course.slug
end
