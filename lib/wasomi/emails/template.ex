defmodule Wasomi.Emails.Template do
  @moduledoc """
  Branded HTML/text shell shared by every transactional email sent from
  `Wasomi.Accounts.UserNotifier`.

  Follows Wasomi's official design system:
    * Deep Navy (`#012c6a`) for headings, brand anchors, and strong typography.
    * High-energy Orange (`#f97316`) for primary action buttons and accents.
    * Neutral slate canvas (`#f8fafc`) with clean white cards and subtle borders.
    * Outfit typography stack.

  `render/1` accepts:

    * `:title` (required) — main heading, shown in both the HTML and text body
    * `:intro` — greeting line, e.g. `"Hi Jane,"`
    * `:body` — a paragraph or list of paragraphs
    * `:cta` — `%{label: string, url: string}` rendered as the primary button
    * `:footer_note` — replaces the default sign-off line

  `:intro`/`:body` entries are plain strings by default (escaped in full) —
  use `rich/1` to bold a name or course title within one instead of hand-
  building HTML at the call site.
  """

  @navy "#012c6a"
  @primary "#f97316"
  @body_color "#334155"
  @muted "#64748b"
  @bg "#f8fafc"
  @border "#e2e8f0"

  @doc "Renders the full HTML document for an email."
  def render(assigns) do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700&display=swap" rel="stylesheet">
      </head>
      <body style="margin:0;padding:0;background-color:#{@bg};font-family:'Outfit',Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;">
        <div style="max-width:580px;margin:0 auto;padding:40px 20px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:20px;overflow:hidden;border:1px solid #{@border};box-shadow:0 4px 20px -2px rgba(1,44,106,0.06);">
            <tr>
              <td style="padding:36px 36px 8px;">#{logo()}</td>
            </tr>
            <tr>
              <td style="padding:12px 36px 36px;">
                <h1 style="margin:0 0 20px;color:#{@navy};font-size:24px;font-weight:700;line-height:1.3;letter-spacing:-0.3px;font-family:'Outfit',Helvetica,Arial,sans-serif;">#{esc(assigns[:title])}</h1>
                #{paragraphs(assigns)}
                #{cta_button(assigns[:cta])}
                #{fallback_link(assigns[:cta])}
              </td>
            </tr>
          </table>
          <div style="margin-top:28px;text-align:center;font-size:12px;color:#{@muted};line-height:1.6;font-family:'Outfit',Helvetica,Arial,sans-serif;">
            <p style="margin:0;color:#94a3b8;">
              #{esc(assigns[:footer_note] || "If you did not request this email, you can safely ignore it.")}
            </p>
          </div>
        </div>
      </body>
    </html>
    """
  end

  @doc """
  Bolds select segments within a paragraph — e.g. a learner's name or a
  course title — without letting call sites inject arbitrary HTML: each
  dynamic value is still escaped individually, `<strong>` is the only tag
  this ever emits, and everything is available as plain text too, for
  `render_text/1`.

  ## Examples

      iex> Wasomi.Emails.Template.rich(["Hi ", {:bold, "Jane"}, "!"])
      {:safe, "Hi <strong>Jane</strong>!", "Hi Jane!"}
  """
  def rich(segments) do
    html =
      Enum.map_join(segments, "", fn
        {:bold, value} -> "<strong>#{esc(value)}</strong>"
        text -> esc(text)
      end)

    plain =
      Enum.map_join(segments, "", fn
        {:bold, value} -> value
        text -> text
      end)

    {:safe, html, plain}
  end

  @doc "Renders the plain-text fallback for an email, mirroring `render/1`."
  def render_text(assigns) do
    intro = plain_text(assigns[:intro])
    body = assigns[:body] |> List.wrap() |> Enum.map(&plain_text/1)
    cta = assigns[:cta]
    url = if is_map(cta), do: Map.get(cta, :url)

    cta_lines =
      if cta && safe_url?(url) do
        ["", "#{Map.get(cta, :label)}: #{url}"]
      else
        []
      end

    [assigns[:title], "", intro]
    |> Kernel.++(body)
    |> Kernel.++(cta_lines)
    |> Kernel.++(["", "- The Wasomi team"])
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp logo do
    url = "#{WasomiWeb.Endpoint.url()}/images/logo.png"

    """
    <div style="display:block;margin-bottom:12px;">
      <img src="#{url}" alt="Wasomi" height="34" style="height:34px;width:auto;display:block;border:0;outline:none;" />
    </div>
    """
  end

  defp paragraphs(assigns) do
    [assigns[:intro] | List.wrap(assigns[:body])]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join("\n", fn paragraph ->
      ~s(<p style="margin:0 0 16px;color:#{@body_color};font-size:15px;line-height:1.65;font-weight:400;font-family:'Outfit',Helvetica,Arial,sans-serif;">#{paragraph_html(paragraph)}</p>)
    end)
  end

  defp paragraph_html({:safe, html, _plain}), do: html
  defp paragraph_html(text), do: esc(text)

  defp plain_text({:safe, _html, plain}), do: plain
  defp plain_text(text), do: text

  defp cta_button(nil), do: ""

  defp cta_button(%{} = cta) do
    label = Map.get(cta, :label)
    url = Map.get(cta, :url)

    if safe_url?(url) do
      """
      <div style="margin:28px 0 12px;">
        <a href="#{esc(url)}" style="display:inline-block;padding:14px 32px;border-radius:9999px;background-color:#{@primary};color:#ffffff;font-size:15px;font-weight:600;text-decoration:none;text-align:center;box-shadow:0 4px 14px rgba(249,115,22,0.28);font-family:'Outfit',Helvetica,Arial,sans-serif;">
          #{esc(label)}
        </a>
      </div>
      """
    else
      ""
    end
  end

  defp fallback_link(nil), do: ""

  defp fallback_link(%{} = cta) do
    url = Map.get(cta, :url)

    if safe_url?(url) do
      """
      <div style="margin-top:28px;padding-top:20px;border-top:1px solid #f1f5f9;font-size:12px;color:#{@muted};line-height:1.5;font-family:'Outfit',Helvetica,Arial,sans-serif;">
        <p style="margin:0 0 6px;">Button not working? Copy and paste this link into your browser:</p>
        <p style="margin:0;word-break:break-all;"><a href="#{esc(url)}" style="color:#{@navy};text-decoration:underline;">#{esc(url)}</a></p>
      </div>
      """
    else
      ""
    end
  end

  defp safe_url?(url) when is_binary(url) do
    trimmed = String.trim(url)
    unwrapped = String.replace(trimmed, "[TOKEN]", "")

    cond do
      String.starts_with?(unwrapped, "//") ->
        false

      String.starts_with?(unwrapped, "/") ->
        true

      URI.parse(unwrapped).scheme in ["http", "https"] ->
        true

      String.starts_with?(trimmed, "[TOKEN]") and String.ends_with?(trimmed, "[TOKEN]") and
          URI.parse(unwrapped).scheme == nil ->
        true

      true ->
        false
    end
  rescue
    _ -> false
  end

  defp safe_url?(_), do: false

  defp esc(nil), do: ""

  defp esc(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
