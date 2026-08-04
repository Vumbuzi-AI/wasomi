defmodule Wasomi.Certificates.Template do
  @moduledoc """
  Branded HEEx certificate template.

  Every visual choice (colors, fonts, borders, watermark) lives entirely in
  this module's `<style>` block — swapping brand colors or layout later is a
  CSS-only change here and never touches the LiveView, renderer, or schema.
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
  attr :signatory_name, :string, default: nil
  attr :signatory_title, :string, default: nil
  attr :signature_url, :string, default: nil

  def certificate(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
        <link
          href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;700;800&family=Dancing+Script:wght@600&display=swap"
          rel="stylesheet"
        />
        <style>
          /* Every size below is in `vw`, not `px`. The certificate is always
             rendered at a fixed 16:9 ratio, but at wildly different absolute
             sizes — a full 1280x720 print canvas for the real PDF vs. a small
             preview iframe in the admin editor. `vw` keeps every element
             proportional to its container at any of those sizes; fixed `px`
             values look right only at one specific width and overflow/collide
             at the others. */
          * { box-sizing: border-box; }
          html, body {
            margin: 0;
            width: 100%;
            height: 100%;
            font-family: "Outfit", "Arial", sans-serif;
            color: #1a1a1a;
          }
          .page {
            position: relative;
            width: 100vw;
            height: 100vh;
            padding: 1.88vw;
            overflow: hidden;
            background: #ffffff;
          }
          .outer-border {
            height: 100%;
            border: 0.31vw solid #002b6b;
            padding: 0.63vw;
          }
          .inner-border {
            position: relative;
            height: 100%;
            border: 0.16vw solid #ce3d0d;
            padding: 2.81vw 3.75vw;
            text-align: center;
            overflow: hidden;
          }
          .watermark {
            position: absolute;
            top: 52%;
            left: 50%;
            transform: translate(-50%, -50%);
            font-size: 11.72vw;
            font-weight: 800;
            letter-spacing: 0.94vw;
            color: #002b6b;
            opacity: 0.03;
            pointer-events: none;
          }
          .serial {
            position: absolute;
            top: 1.25vw;
            right: 2.5vw;
            font-size: 0.86vw;
            font-weight: 400;
            color: #666666;
            letter-spacing: 0.12vw;
            text-transform: uppercase;
          }
          .serial strong { font-weight: 700; color: #ce3d0d; }
          .eyebrow {
            margin-top: 0.94vw;
            color: #ce3d0d;
            font-size: 0.94vw;
            font-weight: 700;
            letter-spacing: 0.22em;
            text-transform: uppercase;
          }
          .logo {
            margin-top: 0.78vw;
            font-size: 1.41vw;
            font-weight: 800;
            letter-spacing: 0.31vw;
            text-transform: uppercase;
            color: #002b6b;
          }
          h1 {
            margin: 1.41vw 0 0;
            font-size: 2.66vw;
            font-weight: 700;
            letter-spacing: 0.08vw;
            text-transform: uppercase;
            color: #1a1a1a;
          }
          .copy { margin-top: 1.41vw; font-size: 1.09vw; font-weight: 300; color: #555555; }
          .name {
            display: inline-block;
            margin: 0.63vw 0;
            padding: 0 3.75vw 0.47vw;
            border-bottom: 0.16vw solid #ce3d0d;
            font-size: 2.5vw;
            font-weight: 600;
            color: #002b6b;
          }
          .reason {
            max-width: 43.75vw;
            margin: 1.25vw auto 0;
            font-size: 1.09vw;
            font-weight: 300;
            line-height: 1.6;
            color: #444444;
          }
          .reason strong { font-weight: 600; color: #1a1a1a; }
          .footer {
            position: absolute;
            bottom: 2.19vw;
            left: 3.75vw;
            right: 3.75vw;
            display: flex;
            justify-content: space-between;
          }
          .footer-item { width: 14.06vw; text-align: center; }
          .footer-item .line { border-top: 0.08vw solid #888888; margin-bottom: 0.47vw; }
          .footer-item .label {
            font-size: 0.78vw;
            font-weight: 400;
            color: #666666;
            text-transform: uppercase;
            letter-spacing: 0.08vw;
          }
          .footer-item .value {
            font-size: 1.02vw;
            font-weight: 600;
            color: #1a1a1a;
            margin-bottom: 0.16vw;
          }
          .signature-name {
            font-family: "Dancing Script", cursive;
            font-size: 2.19vw;
            font-weight: 600;
            color: #1a1a1a;
            margin-bottom: -0.16vw;
          }
          .signature-image { height: 3.13vw; object-fit: contain; margin-bottom: 0.31vw; }
        </style>
      </head>
      <body>
        <main class="page">
          <div class="outer-border">
            <div class="inner-border">
              <div class="watermark">{watermark_initials(@issuer_name)}</div>

              <div class="serial">Serial no: <strong>{@serial_number}</strong></div>

              <div class="eyebrow">{@type_label}</div>
              <div class="logo">{@issuer_name}</div>

              <h1>Certificate of Completion</h1>
              <div class="copy">This certifies that</div>
              <div class="name">{@learner_name}</div>
              <div class="reason">
                has successfully completed <strong>{@title}</strong>
              </div>

              <div class="footer">
                <div class="footer-item">
                  <div class="value">{@issued_on}</div>
                  <div class="line"></div>
                  <div class="label">Date issued</div>
                </div>

                <div :if={@signatory_name} class="footer-item">
                  <img :if={@signature_url} src={@signature_url} alt="" class="signature-image" />
                  <div :if={!@signature_url} class="signature-name">{@signatory_name}</div>
                  <div class="line"></div>
                  <div class="label">{@signatory_title || "Authorized signatory"}</div>
                </div>
              </div>
            </div>
          </div>
        </main>
      </body>
    </html>
    """
  end

  defp watermark_initials(issuer_name) do
    issuer_name
    |> to_string()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end
end
