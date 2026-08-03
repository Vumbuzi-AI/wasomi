defmodule Wasomi.Emails.Template do
  @moduledoc """
  Branded HTML/text shell shared by every transactional email sent from
  `Wasomi.Accounts.UserNotifier`.

  Colors and the logo mark mirror `assets/tailwind.config.js` — the source of
  truth for brand tokens — not `design.md`, which is currently stale (it still
  documents the old green palette).

  `render/1` accepts:

    * `:title` (required) — main heading, shown in both the HTML and text body
    * `:intro` — greeting line, e.g. `"Hi Jane,"`
    * `:body` — a paragraph or list of paragraphs
    * `:cta` — `%{label: string, url: string}` rendered as the primary button
    * `:footer_note` — replaces the default sign-off line
  """

  @primary "#f97316"
  @dark "#0a0a0a"
  @body_color "#404040"
  @muted "#a3a3a3"
  @mint "#fff7ed"

  @doc "Renders the full HTML document for an email."
  def render(assigns) do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400&display=swap" rel="stylesheet">
      </head>
      <body style="margin:0;padding:0;background-color:#{@mint};font-family:'Outfit',Helvetica,Arial,sans-serif;font-weight:400;">
        <div style="max-width:560px;margin:0 auto;padding:40px 20px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:24px;overflow:hidden;border:1px solid rgba(0,0,0,0.06);">
            <tr>
              <td style="padding:32px 32px 8px;">#{logo()}</td>
            </tr>
            <tr>
              <td style="padding:16px 32px 40px;">
                <h1 style="margin:0 0 20px;color:#{@dark};font-size:22px;font-weight:400;line-height:1.35;">#{esc(assigns[:title])}</h1>
                #{paragraphs(assigns)}
                #{cta_button(assigns[:cta])}
              </td>
            </tr>
          </table>
          <p style="margin:24px 8px 0;color:#{@muted};font-size:12px;text-align:center;font-weight:400;">
            #{esc(assigns[:footer_note] || "This message was sent by Wasomi Business Institute.")}
          </p>
        </div>
      </body>
    </html>
    """
  end

  @doc "Renders the plain-text fallback for an email, mirroring `render/1`."
  def render_text(assigns) do
    intro = assigns[:intro]
    body = List.wrap(assigns[:body])
    cta = assigns[:cta]

    [assigns[:title], "", intro]
    |> Kernel.++(body)
    |> Kernel.++(if cta, do: ["", "#{cta.label}: #{cta.url}"], else: [])
    |> Kernel.++(["", "- The Wasomi team"])
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp logo do
    """
    <div style="display:flex;align-items:center;gap:10px;">
      <span style="display:inline-block;width:32px;height:32px;border-radius:999px;background-color:#{@primary};text-align:center;line-height:32px;">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" style="vertical-align:middle;">
          <path d="M5 18V8l7 7 7-7v10" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
        </svg>
      </span>
      <span style="font-size:18px;font-weight:400;color:#{@dark};">Wasomi</span>
    </div>
    """
  end

  defp paragraphs(assigns) do
    [assigns[:intro] | List.wrap(assigns[:body])]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join("\n", fn paragraph ->
      ~s(<p style="margin:0 0 16px;color:#{@body_color};font-size:15px;line-height:1.6;font-weight:400;">#{esc(paragraph)}</p>)
    end)
  end

  defp cta_button(nil), do: ""

  defp cta_button(%{label: label, url: url}) do
    """
    <a href="#{esc(url)}" style="display:inline-block;margin-top:8px;padding:14px 28px;border-radius:999px;background-color:#{@dark};color:#ffffff;font-size:15px;font-weight:400;text-decoration:none;">
      #{esc(label)}
    </a>
    """
  end

  defp esc(nil), do: ""

  defp esc(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
