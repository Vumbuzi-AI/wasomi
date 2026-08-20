defmodule Wasomi.Certificates.Template do
  @moduledoc """
  Branded HEEx certificate template.

  A two-column landscape design: a narrow left rail carrying the institution's
  logo, an embossed gold seal and its contact details, beside a main column
  holding the award copy and signatures.

  Every visual choice (colors, fonts, the seal, the QR placeholder) lives
  entirely in this module's `<style>` block — swapping brand colors or layout
  later is a CSS-only change here and never touches the LiveView, renderer, or
  schema. The seal and QR block are drawn in pure CSS rather than shipped as
  images, so there are no binary assets to keep in sync with the palette.
  """

  use Phoenix.Component

  alias Phoenix.HTML.Safe

  def render_html(assigns) do
    assigns
    |> certificate()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  attr :learner_name, :string, required: true
  attr :title, :string, required: true
  attr :type_label, :string, required: true
  attr :issued_on, :string, required: true
  attr :serial_number, :string, required: true
  attr :issuer_name, :string, default: "Wasomi Business Institute"

  attr :headline, :string, default: "Certificate of Completion"
  attr :presented_line, :string, default: "This is proudly presented to"
  attr :citation, :string, default: "in recognition of successful completion of the"

  attr :signatory_name, :string, default: nil
  attr :signatory_title, :string, default: nil
  attr :signature_url, :string, default: nil
  attr :signatory_two_name, :string, default: nil
  attr :signatory_two_title, :string, default: nil
  attr :signatory_two_signature_url, :string, default: nil

  # Left-rail branding, supplied by Wasomi.Certificates.Branding. Each is
  # optional and its block collapses when absent.
  attr :logo_data_uri, :string, default: nil
  attr :address_lines, :list, default: []
  attr :phone, :string, default: nil
  attr :email, :string, default: nil
  attr :website, :string, default: nil
  attr :socials, :list, default: []

  # Supply a `data:image/png;base64,...` URI to print a real, scannable QR in
  # place of the CSS placeholder. Nothing else needs to change.
  attr :qr_data_uri, :string, default: nil

  def certificate(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
        <link
          href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800&family=Dancing+Script:wght@600&display=swap"
          rel="stylesheet"
        />
        <style>
          /* Every size below is in `vw`, not `px` — including vertical ones.
             The certificate renders at a fixed A4-landscape ratio but at wildly
             different absolute sizes: a full 1123x794pt print canvas for the
             real PDF vs. a small preview iframe in the admin editor. `vw` keeps
             every element proportional to its container at any of those sizes;
             fixed `px` values look right only at one specific width and
             overflow/collide at the others, and `vh` would decouple vertical
             rhythm from horizontal. */
          * { box-sizing: border-box; }
          html, body {
            margin: 0;
            width: 100%;
            height: 100%;
            background: #ffffff;
            font-family: "Outfit", "DejaVu Sans", "Verdana", sans-serif;
            color: #333333;
          }
          .page {
            display: flex;
            width: 100vw;
            height: 100vh;
            padding: 3.8vw 4.2vw;
            overflow: hidden;
          }

          /* ---------- Left rail ---------- */
          .rail {
            display: flex;
            flex-direction: column;
            flex-shrink: 0;
            width: 23vw;
          }
          .logo { width: 15vw; object-fit: contain; object-position: left top; }
          /* Wordmark fallback when no logo file is configured or readable. */
          .logo-wordmark {
            font-size: 1.9vw;
            font-weight: 800;
            line-height: 1.15;
            letter-spacing: 0.06vw;
            text-transform: uppercase;
            color: #002c6c;
          }

          /* Embossed gold seal, drawn entirely in CSS.
             - the rim is a repeating conic gradient, which reads as the
               scalloped/serrated edge of a foil seal
             - the face is an off-centre radial gradient, so the highlight sits
               up and to the left like light falling on raised foil
             - inset shadows supply the emboss; the outer shadow lifts it off
               the page */
          .seal-wrap { margin: auto 0; }
          .seal {
            position: relative;
            display: flex;
            align-items: center;
            justify-content: center;
            width: 12.5vw;
            height: 12.5vw;
            border-radius: 50%;
            background: repeating-conic-gradient(
              from 0deg,
              #8a6a1c 0deg 5deg,
              #f2d886 5deg 10deg
            );
            box-shadow: 0 0.12vw 0.45vw rgba(0, 0, 0, 0.28);
          }
          .seal::before {
            content: "";
            position: absolute;
            inset: 0.75vw;
            border-radius: 50%;
            background: radial-gradient(
              circle at 34% 28%,
              #fdf3c4 0%,
              #ecd074 34%,
              #c9a333 68%,
              #8f6d1d 100%
            );
            box-shadow:
              inset 0 0 0.55vw rgba(255, 255, 255, 0.6),
              inset 0 -0.22vw 0.55vw rgba(0, 0, 0, 0.3);
          }
          .seal::after {
            content: "";
            position: absolute;
            inset: 1.65vw;
            border: 0.1vw solid rgba(94, 71, 15, 0.45);
            border-radius: 50%;
          }
          .seal-inner {
            position: relative;
            z-index: 1;
            text-align: center;
            color: #5e470f;
          }
          .seal-initials {
            font-size: 3vw;
            font-weight: 800;
            line-height: 1;
            letter-spacing: 0.12vw;
            text-shadow: 0 0.05vw 0 rgba(255, 255, 255, 0.5);
          }
          .seal-caption {
            margin-top: 0.25vw;
            font-size: 0.62vw;
            font-weight: 700;
            letter-spacing: 0.14vw;
            text-transform: uppercase;
          }

          .contact { font-size: 0.86vw; line-height: 1.65; color: #4a4a4a; }
          .contact-org {
            margin-bottom: 0.15vw;
            font-size: 0.92vw;
            font-weight: 700;
            color: #002c6c;
          }
          .contact-group { margin-top: 0.9vw; }
          .contact-key { font-weight: 700; color: #f26334; }
          .contact-socials {
            margin-top: 0.9vw;
            font-size: 0.86vw;
            color: #1f5fa9;
          }

          /* ---------- Main column ---------- */
          .main {
            display: flex;
            flex: 1;
            flex-direction: column;
            min-width: 0;
            padding-left: 4.4vw;
          }
          .main-head {
            display: flex;
            flex-shrink: 0;
            flex-direction: column;
            align-items: flex-end;
          }
          .qr { width: 8.6vw; height: 8.6vw; display: block; image-rendering: pixelated; }
          /* CSS stand-in for a real QR: a fine checkerboard for the data area
             plus the three corner finder squares that make a QR legible as one
             at a glance. Swap in `qr_data_uri` for a scannable code. */
          .qr-placeholder {
            position: relative;
            width: 8.6vw;
            height: 8.6vw;
            background-color: #ffffff;
            background-image: conic-gradient(
              #1a1a1a 25%,
              #ffffff 25% 50%,
              #1a1a1a 50% 75%,
              #ffffff 75%
            );
            background-size: 0.62vw 0.62vw;
          }
          .qr-eye {
            position: absolute;
            width: 2.5vw;
            height: 2.5vw;
            background: #ffffff;
            box-shadow:
              inset 0 0 0 0.42vw #1a1a1a,
              inset 0 0 0 0.84vw #ffffff,
              inset 0 0 0 1.26vw #1a1a1a;
          }
          .qr-eye.tl { top: 0; left: 0; }
          .qr-eye.tr { top: 0; right: 0; }
          .qr-eye.bl { bottom: 0; left: 0; }
          .serial {
            margin-top: 0.5vw;
            font-size: 0.95vw;
            font-weight: 700;
            letter-spacing: 0.02vw;
            color: #1a1a1a;
            white-space: nowrap;
          }
          .top-rule {
            flex-shrink: 0;
            height: 0.42vw;
            margin: 1.1vw 0 0;
            background: #f26334;
          }

          /* Vertically centred in the space left between the rule and the
             signatures, so the copy sits balanced no matter how long the name
             or course title runs. */
          .content {
            display: flex;
            flex: 1;
            flex-direction: column;
            justify-content: center;
            min-width: 0;
          }
          .eyebrow {
            margin-bottom: 0.5vw;
            font-size: 0.92vw;
            font-weight: 700;
            letter-spacing: 0.22em;
            text-transform: uppercase;
            color: #7a7a7a;
          }
          .headline {
            margin: 0;
            font-size: 4.1vw;
            font-weight: 400;
            line-height: 1.1;
            letter-spacing: -0.03vw;
            color: #f26334;
          }          .lede { margin-top: 0.5vw; font-size: 1.55vw; font-weight: 400; color: #3d3d3d; }
          .name {
            margin-top: 1.3vw;
            font-size: 3.9vw;
            font-weight: 700;
            line-height: 1.08;
            letter-spacing: -0.05vw;
            color: #002c6c;
            overflow-wrap: break-word;
          }
          .citation { margin-top: 1.3vw; font-size: 1.55vw; font-weight: 400; color: #3d3d3d; }
          .award {
            margin-top: 0.55vw;
            font-size: 2.35vw;
            font-weight: 500;
            line-height: 1.28;
            color: #f26334;
            overflow-wrap: break-word;
          }
          .issued { margin-top: 1.15vw; font-size: 1.55vw; font-weight: 400; color: #3d3d3d; }

          /* ---------- Signatures ---------- */
          .signatures {
            display: flex;
            flex-shrink: 0;
            gap: 4.5vw;
            margin-top: 1.6vw;
          }
          .signatory { width: 15vw; text-align: center; }
          /* Fixed-height slot so the orange rules line up across both
             signatories whether one has an uploaded image and the other falls
             back to cursive type. */
          .signature-slot {
            display: flex;
            align-items: flex-end;
            justify-content: center;
            height: 3.9vw;
          }
          .signature-image { max-width: 100%; max-height: 3.9vw; object-fit: contain; }
          .signature-name {
            font-family: "Dancing Script", cursive;
            font-size: 2.5vw;
            font-weight: 600;
            line-height: 1.1;
            color: #1a1a1a;
          }
          .signature-rule { height: 0.16vw; margin-bottom: 0.4vw; background: #f26334; }
          .signatory-name {
            font-size: 1.3vw;
            font-weight: 700;
            line-height: 1.25;
            color: #002c6c;
          }
          .signatory-title { font-size: 1.05vw; font-weight: 400; color: #4a4a4a; }
        </style>
      </head>
      <body>
        <main class="page">
          <aside class="rail">
            <img :if={@logo_data_uri} src={@logo_data_uri} alt="" class="logo" />
            <div :if={!@logo_data_uri} class="logo-wordmark">{@issuer_name}</div>

            <div class="seal-wrap">
              <div class="seal">
                <div class="seal-inner">
                  <div class="seal-initials">{initials(@issuer_name)}</div>
                  <div class="seal-caption">Certified</div>
                </div>
              </div>
            </div>

            <div class="contact">
              <div class="contact-org">{@issuer_name}</div>
              <div :for={line <- @address_lines}>{line}</div>

              <div :if={@phone || @email || @website} class="contact-group">
                <div :if={@phone}><span class="contact-key">T</span> {@phone}</div>
                <div :if={@email}><span class="contact-key">E</span> {@email}</div>
                <div :if={@website}>{@website}</div>
              </div>

              <div :if={@socials != []} class="contact-socials">
                {Enum.join(@socials, " | ")}
              </div>
            </div>
          </aside>

          <section class="main">
            <div class="main-head">
              <img :if={@qr_data_uri} src={@qr_data_uri} alt="" class="qr" />
              <div :if={!@qr_data_uri} class="qr-placeholder">
                <span class="qr-eye tl"></span>
                <span class="qr-eye tr"></span>
                <span class="qr-eye bl"></span>
              </div>
              <div class="serial">{@serial_number}</div>
            </div>

            <div class="top-rule"></div>

            <div class="content">
              <div class="eyebrow">{@type_label}</div>
              <h1 class="headline">{@headline}</h1>
              <div class="lede">{@presented_line}</div>
              <div class="name">{@learner_name}</div>
              <div class="citation">{@citation}</div>
              <div class="award">{@title}</div>
              <div class="issued">On {@issued_on}</div>
            </div>

            <div :if={@signatory_name} class="signatures">
              <div class="signatory">
                <div class="signature-slot">
                  <img
                    :if={@signature_url}
                    src={@signature_url}
                    alt=""
                    class="signature-image"
                  />
                  <div :if={!@signature_url} class="signature-name">{@signatory_name}</div>
                </div>
                <div class="signature-rule"></div>
                <div class="signatory-name">{@signatory_name}</div>
                <div class="signatory-title">{@signatory_title || "Authorized signatory"}</div>
              </div>

              <div :if={@signatory_two_name} class="signatory">
                <div class="signature-slot">
                  <img
                    :if={@signatory_two_signature_url}
                    src={@signatory_two_signature_url}
                    alt=""
                    class="signature-image"
                  />
                  <div :if={!@signatory_two_signature_url} class="signature-name">
                    {@signatory_two_name}
                  </div>
                </div>
                <div class="signature-rule"></div>
                <div class="signatory-name">{@signatory_two_name}</div>
                <div class="signatory-title">
                  {@signatory_two_title || "Authorized signatory"}
                </div>
              </div>
            </div>
          </section>
        </main>
      </body>
    </html>
    """
  end

  defp initials(issuer_name) do
    issuer_name
    |> to_string()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end
end
