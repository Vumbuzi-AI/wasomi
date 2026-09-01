defmodule Wasomi.Receipts.Template do
  @moduledoc """
  Branded payment-receipt template.

  A formal document: logo + "Receipt / Paid in full / No. / Issued" header,
  then calm left-aligned sections separated by full-width hairlines —
  order summary, totals (with the one navy accent), and a compact legal footer.
  The payment reference sits with the purchased item so the receipt reads as one
  tidy transaction. Typeset in Wasomi's Outfit.

  The logo and fonts are embedded as base64 data URIs at compile time, so a
  render never touches the network or the filesystem.
  """

  use Phoenix.Component

  alias Phoenix.HTML.Safe

  priv = :code.priv_dir(:wasomi)

  assets = %{
    outfit_latin: Path.join(priv, "certificate_fonts/outfit-latin.woff2"),
    outfit_latin_ext: Path.join(priv, "certificate_fonts/outfit-latin-ext.woff2"),
    wasomi_logo: Path.join(priv, "static/images/logo.png")
  }

  for {_key, path} <- assets, do: @external_resource(path)

  data_uri = fn path, mime -> "data:#{mime};base64," <> (File.read!(path) |> Base.encode64()) end

  @wasomi_logo data_uri.(assets.wasomi_logo, "image/png")

  @font_face_css """
  @font-face {
    font-family: "Outfit";
    font-style: normal;
    font-weight: 100 900;
    src: url(#{data_uri.(assets.outfit_latin_ext, "font/woff2")}) format("woff2");
    unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
  }
  @font-face {
    font-family: "Outfit";
    font-style: normal;
    font-weight: 100 900;
    src: url(#{data_uri.(assets.outfit_latin, "font/woff2")}) format("woff2");
    unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
  }
  """

  @doc "Renders the receipt component to an HTML string for the PDF renderer."
  def render_html(assigns) do
    assigns
    |> Map.merge(%{font_face_css: @font_face_css, wasomi_logo: @wasomi_logo})
    |> receipt()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  attr :issuer_name, :string, required: true
  attr :address_lines, :list, default: []
  attr :issuer_email, :string, default: nil
  attr :issuer_website, :string, default: nil
  attr :receipt_no, :string, required: true
  attr :reference, :string, required: true
  attr :issued_on, :string, required: true
  attr :billed_to_name, :string, required: true
  attr :billed_to_email, :string, required: true
  attr :course_title, :string, required: true
  attr :amount, :string, required: true
  attr :tax, :string, required: true
  attr :payment_method, :string, required: true
  attr :font_face_css, :string, required: true
  attr :wasomi_logo, :string, required: true

  def receipt(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <style>
          <%= Phoenix.HTML.raw(@font_face_css) %>
        </style>
        <style>
          :root {
            --ink: #012c6a;
            --text: #2b2b2b;
            --muted: #6b6b6b;
            --hair: #e6e6e6;
            --paid: #1c7a48;
          }
          * { box-sizing: border-box; }
          html, body { margin: 0; padding: 0; }
          body {
            font-family: "Outfit", "Helvetica Neue", Arial, sans-serif;
            color: var(--text);
            font-size: 13px;
            line-height: 1.6;
            font-variant-numeric: tabular-nums;
            -webkit-font-smoothing: antialiased;
          }
          a { color: var(--ink); text-decoration: none; }

          .label {
            font-size: 9px; font-weight: 700; letter-spacing: 0.9px;
            text-transform: uppercase; color: var(--muted);
          }
          .num { font-variant-numeric: tabular-nums; }

          /* Header */
          .header {
            display: flex; justify-content: space-between; align-items: flex-start;
            padding-bottom: 20px; margin-bottom: 30px; border-bottom: 2px solid var(--ink);
          }
          .header img { height: 26px; width: auto; display: block; }
          .doc { text-align: right; line-height: 1.5; }
          .doc .kind {
            font-size: 16px; font-weight: 700; letter-spacing: 3px;
            text-transform: uppercase; color: var(--ink);
          }
          .doc .paid {
            font-size: 9px; font-weight: 700; letter-spacing: 1.2px;
            text-transform: uppercase; color: var(--paid);
          }
          .doc .meta { margin-top: 4px; font-size: 11.5px; color: var(--muted); }
          .doc .meta strong { color: var(--ink); font-weight: 600; }

          .rule { border: 0; border-top: 1px solid var(--hair); margin: 30px 0; }

          h2 {
            margin: 0 0 14px; font-size: 12px; font-weight: 700; letter-spacing: 0.7px;
            text-transform: uppercase; color: var(--muted);
          }

          .line { display: flex; justify-content: space-between; gap: 24px; padding: 7px 0; }
          .line .amt { white-space: nowrap; }
          .item .t { color: var(--ink); font-weight: 500; }
          .item .s { color: var(--muted); font-size: 10.5px; }

          .totals { width: 260px; margin-left: auto; }
          .totals .line .k { color: var(--muted); }
          .totals .grand {
            margin-top: 12px; display: flex; justify-content: space-between; align-items: center;
            background: var(--ink); color: #fff; padding: 12px 16px;
          }
          .totals .grand .k {
            font-size: 10px; font-weight: 700; letter-spacing: 1px; text-transform: uppercase;
          }
          .totals .grand .v { font-size: 15px; font-weight: 700; }

          /* Two parties, laid out as facing address blocks. */
          .parties {
            display: flex; justify-content: space-between; align-items: flex-start;
            gap: 48px; margin-bottom: 28px;
          }
          .party { max-width: 46%; }
          .party.from { text-align: right; }
          .party h3 {
            margin: 0 0 6px; font-size: 12.5px; font-weight: 700;
            color: var(--text); text-transform: none; letter-spacing: 0;
          }
          .party .name { color: var(--ink); font-weight: 600; }
          .party .addr { color: var(--muted); font-size: 11.5px; line-height: 1.7; }
          .party .addr div { word-break: break-word; }

          .ref { word-break: break-all; }

          .foot {
            font-size: 10.5px; color: var(--muted); line-height: 1.7;
            text-align: center; max-width: 440px; margin: 0 auto;
          }
          .foot strong { color: var(--ink); font-weight: 600; }
        </style>
      </head>
      <body>
        <div class="header">
          <img src={@wasomi_logo} alt="Wasomi" />
          <div class="doc">
            <div class="kind">Receipt</div>
            <div class="paid">Paid in full</div>
            <div class="meta">No. <strong>{@receipt_no}</strong></div>
            <div class="meta">Issued {@issued_on}</div>
          </div>
        </div>

        <div class="parties">
          <div class="party to">
            <h3>Billed to</h3>
            <div class="name">{@billed_to_name}</div>
            <div class="addr">
              <div>{@billed_to_email}</div>
            </div>
          </div>
          <div class="party from">
            <h3>From</h3>
            <div class="name">{@issuer_name}</div>
            <div class="addr">
              <div :for={line <- @address_lines}>{line}</div>
              <div :if={@issuer_email}>{@issuer_email}</div>
              <div :if={@issuer_website}>{@issuer_website}</div>
            </div>
          </div>
        </div>

        <h2>Order summary</h2>
        <div class="line item">
          <div>
            <div class="t">{@course_title}</div>
            <div class="s">Course enrolment · Qty 1</div>
            <div class="s">Payment ref · <span class="ref">{@reference}</span></div>
          </div>
          <div class="amt num">{@amount}</div>
        </div>

        <hr class="rule" />

        <div class="totals">
          <div class="line"><span class="k">Subtotal</span><span class="num">{@amount}</span></div>
          <div class="line"><span class="k">Tax</span><span class="num">{@tax}</span></div>
          <div class="grand">
            <span class="k">Total paid</span><span class="v num">{@amount}</span>
          </div>
        </div>

        <hr class="rule" />

        <div class="foot">
          <strong>Computer-generated receipt — no signature required.</strong>
          Issued via Wasomi on behalf of {@issuer_name}.
        </div>
      </body>
    </html>
    """
  end
end
