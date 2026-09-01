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

  # Self-hosted as base64 data URIs, embedded at compile time, rather than
  # linked from Google Fonts. ChromicPDF's render blocks on
  # `document.fonts.ready` (see the renderer), so a live webfont fetch put
  # every certificate render at the mercy of network conditions inside the
  # headless Chrome sandbox for no real benefit — these two families are
  # tiny (under 90KB total) and never change at runtime. `@external_resource`
  # tells Mix to recompile this module if a font file is swapped.
  fonts_dir = Path.join(:code.priv_dir(:wasomi), "certificate_fonts")

  for filename <-
        ~w(outfit-latin.woff2 outfit-latin-ext.woff2 dancing-script-latin.woff2 dancing-script-latin-ext.woff2) do
    @external_resource Path.join(fonts_dir, filename)
  end

  outfit_latin = Path.join(fonts_dir, "outfit-latin.woff2") |> File.read!() |> Base.encode64()

  outfit_latin_ext =
    Path.join(fonts_dir, "outfit-latin-ext.woff2") |> File.read!() |> Base.encode64()

  dancing_script_latin =
    Path.join(fonts_dir, "dancing-script-latin.woff2") |> File.read!() |> Base.encode64()

  dancing_script_latin_ext =
    Path.join(fonts_dir, "dancing-script-latin-ext.woff2") |> File.read!() |> Base.encode64()

  @font_face_css """
  @font-face {
    font-family: "Outfit";
    font-style: normal;
    font-weight: 100 900;
    src: url(data:font/woff2;base64,#{outfit_latin_ext}) format("woff2");
    unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
  }
  @font-face {
    font-family: "Outfit";
    font-style: normal;
    font-weight: 100 900;
    src: url(data:font/woff2;base64,#{outfit_latin}) format("woff2");
    unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
  }
  @font-face {
    font-family: "Dancing Script";
    font-style: normal;
    font-weight: 600;
    src: url(data:font/woff2;base64,#{dancing_script_latin_ext}) format("woff2");
    unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
  }
  @font-face {
    font-family: "Dancing Script";
    font-style: normal;
    font-weight: 600;
    src: url(data:font/woff2;base64,#{dancing_script_latin}) format("woff2");
    unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
  }
  """

  def render_html(assigns) do
    assigns
    |> certificate()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  attr :learner_name, :string, required: true
  attr :title, :string, required: true
  attr :issued_on, :string, required: true

  attr :gdti, :string,
    required: true,
    doc:
      "Raw digits only (no \"253\" prefix — that's the GS1 Application " <>
        "Identifier, added as a printed label at render time, not part " <>
        "of the identifier's own value)"

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
  attr :icon_strip_data_uri, :string, default: nil
  attr :seal_data_uri, :string, default: nil

  # Supply a `data:image/png;base64,...` URI to print a real, scannable QR in
  # place of the CSS placeholder. Nothing else needs to change.
  attr :qr_data_uri, :string, default: nil
  attr :preview?, :boolean, default: false

  # A sample/marketing render (e.g. the course page preview) — suppresses the
  # printed GDTI so a non-issued certificate never displays a real identifier.
  attr :sample?, :boolean, default: false

  def certificate(assigns) do
    # `@name` inside `~H` always reads `assigns.name`, never a module
    # attribute — so the compiled font CSS has to be threaded through as an
    # assign to reach the template below. Plain `Map.put/3`, not
    # `Phoenix.Component.assign/2`: `render_html/1` calls this function
    # directly with a bare map rather than through `<.certificate .../>`, so
    # the change-tracking metadata `assign/2` requires isn't present.
    assigns =
      assigns
      |> Map.put(:font_face_css, @font_face_css)
      |> Map.put_new(:sample?, false)

    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <style>
          <%= Phoenix.HTML.raw(@font_face_css) %>
        </style>
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
          body.preview { overflow: hidden; }
          .page {
            display: flex;
            width: 100vw;
            height: 100vh;
            padding: 4.6vw 5vw 2.4vw;
            overflow: hidden;
          }

          /* ---------- Left rail ---------- */
          .rail {
            display: flex;
            flex-direction: column;
            flex-shrink: 0;
            width: 26vw;
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

          .seal-wrap { margin: 7vw 0 4vw; }
          .seal { display: block; width: 17vw; height: 17vw; object-fit: contain; }
          .contact { font-size: 1.3vw; line-height: 1.7; color: #4a4a4a; }
          .contact-org {
            margin-bottom: 0.25vw;
            font-size: 1.4vw;
            font-weight: 700;
            color: #002c6c;
          }
          .contact-group { margin-top: 1.1vw; }
          .contact-key { font-weight: 700; color: #f26334; }
          .contact-socials {
            margin-top: 1.1vw;
            font-size: 1.3vw;
            color: #1f5fa9;
          }
          .contact-socials a { color: inherit; text-decoration: none; }

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
          body.preview .main-head { padding-right: 0.8vw; }
          .qr { width: 7.6vw; height: 7.6vw; display: block; image-rendering: pixelated; }
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
            margin: 1.1vw 0 0.4vw;
            background: #f26334;
          }

          /* Vertically centred in the space left between the rule and the
             signatures, so the copy sits balanced no matter how long the name
             or course title runs. */
          .content {
            display: flex;
            flex: 1;
            flex-direction: column;
            justify-content: flex-start;
            min-width: 0;
          }
          .headline {
            margin: 0;
            font-size: 4.1vw;
            font-weight: 400;
            line-height: 1.1;
            letter-spacing: -0.03vw;
            color: #f26334;
          }          .lede { margin-top: 0.5vw; font-size: 1.85vw; font-weight: 400; color: #3d3d3d; }
          .name {
            margin-top: 1.3vw;
            font-size: 3.9vw;
            font-weight: 700;
            line-height: 1.08;
            letter-spacing: -0.05vw;
            color: #002c6c;
            overflow-wrap: break-word;
          }
          .citation { margin-top: 1.3vw; font-size: 1.85vw; font-weight: 400; color: #3d3d3d; }
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
          /* 80% (not 100%) so the second signatory's right edge lines up
             with the end of the headline above — "Certificate of
             Completion" is a fixed string, always this same width, so this
             holds for every real certificate. */
          .signatures {
            display: flex;
            flex-shrink: 0;
            justify-content: space-between;
            width: 80%;
            gap: 4vw;
            margin-top: 1.6vw;
          }
          .signatory { flex: 0 1 auto; min-width: 12vw; text-align: center; }
          /* Fixed-height slot so the orange rules line up across both
             signatories whether one has an uploaded image and the other falls
             back to cursive type. */
          .signature-slot {
            display: flex;
            align-items: flex-end;
            justify-content: center;
            height: 3vw;
          }
          /* `width: 100%` (not the image's own intrinsic size) so an
             uploaded signature always spans the same width as the printed
             name/rule below it — otherwise a narrow scan under a long name
             reads as a small, disconnected chip rather than a signature. */
          .signature-image { width: 100%; height: auto; max-height: 3vw; object-fit: contain; }
          .signature-name {
            font-family: "Dancing Script", cursive;
            font-size: 1.9vw;
            font-weight: 600;
            line-height: 1.1;
            white-space: nowrap;
            color: #1a1a1a;
          }
          .signature-rule {
            height: 0.16vw;
            margin-top: 0.4vw;
            margin-bottom: 0.4vw;
            background: #f26334;
          }
          .signatory-name {
            font-size: 1.3vw;
            font-weight: 700;
            line-height: 1.25;
            color: #002c6c;
          }
          .signatory-title { font-size: 1.05vw; font-weight: 400; color: #002c6c; }

          .icon-strip {
            flex-shrink: 0;
            width: 100%;
            height: auto;
            margin-top: 0.6vw;
            object-fit: contain;
            object-position: left;
          }
        </style>
      </head>
      <body class={if @preview?, do: "preview"}>
        <main class="page">
          <aside class="rail">
            <img :if={@logo_data_uri} src={@logo_data_uri} alt="" class="logo" />
            <div :if={!@logo_data_uri} class="logo-wordmark">{@issuer_name}</div>

            <div class="seal-wrap">
              <img :if={@seal_data_uri} src={@seal_data_uri} alt="" class="seal" />
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
                <span :for={{{label, url}, index} <- Enum.with_index(@socials)}>
                  <span :if={index > 0}> | </span><a
                    :if={url}
                    href={url}
                    target="_blank"
                    rel="noopener noreferrer"
                  >{label}</a><span :if={!url}>{label}</span>
                </span>
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
              <div :if={not @sample? and @gdti not in [nil, ""]} class="serial">
                (253) {@gdti}
              </div>
            </div>

            <div class="top-rule"></div>

            <div class="content">
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
                  <img :if={@signature_url} src={@signature_url} alt="" class="signature-image" />
                  <div :if={!@signature_url} class="signature-name">{@signatory_name}</div>
                </div>
                <div class="signature-rule"></div>
                <div class="signatory-name">{@signatory_name}</div>
                <div class="signatory-title">{@signatory_title || "Authorized signatory"}</div>
                <div class="signature-rule"></div>
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
                <div class="signature-rule"></div>
              </div>
            </div>

            <img :if={@icon_strip_data_uri} src={@icon_strip_data_uri} alt="" class="icon-strip" />
          </section>
        </main>
      </body>
    </html>
    """
  end
end
