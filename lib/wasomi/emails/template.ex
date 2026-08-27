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

  `:intro`/`:body` entries are plain strings by default (escaped in full) —
  use `rich/1` to bold a name or course title within one instead of hand-
  building HTML at the call site.
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

  # Most mail clients strip/block remote images by default, so the real
  # logo is inlined as a data URI rather than linked — guarantees it shows
  # up without the recipient needing to click "show images". Cached in
  # `:persistent_term`: this renders on every transactional email sent, and
  # re-reading + re-encoding the same ~56 KB file each time isn't free.
  defp logo do
    case logo_data_uri() do
      nil ->
        ~s(<span style="font-size:18px;font-weight:600;color:#{@dark};">Wasomi</span>)

      data_uri ->
        ~s(<img src="#{data_uri}" alt="Wasomi" height="28" style="display:block;height:28px;width:auto;">)
    end
  end

  defp logo_data_uri do
    :persistent_term.get({__MODULE__, :logo_data_uri}, nil) || load_and_cache_logo()
  end

  defp load_and_cache_logo do
    data_uri =
      case Application.app_dir(:wasomi, "priv/static/images/logo.png") |> File.read() do
        {:ok, bytes} -> "data:image/png;base64,#{Base.encode64(bytes)}"
        {:error, _reason} -> nil
      end

    :persistent_term.put({__MODULE__, :logo_data_uri}, data_uri)
    data_uri
  end

  defp paragraphs(assigns) do
    [assigns[:intro] | List.wrap(assigns[:body])]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join("\n", fn paragraph ->
      ~s(<p style="margin:0 0 16px;color:#{@body_color};font-size:15px;line-height:1.6;font-weight:400;">#{paragraph_html(paragraph)}</p>)
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
      <a href="#{esc(url)}" style="display:inline-block;margin-top:8px;padding:14px 28px;border-radius:999px;background-color:#{@primary};color:#ffffff;font-size:15px;font-weight:600;text-decoration:none;">
        #{esc(label)}
      </a>
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
