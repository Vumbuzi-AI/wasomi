defmodule Wasomi.Content.LandingPreview do
  @moduledoc """
  Renders a scoped, static snapshot of the real public-homepage section for
  one landing-image slot — used by the admin editor's live preview iframe so
  an admin sees the *actual* page markup (the hero banner, or the relevant
  "See GS1 in action" step), including a not-yet-saved pick, instead of just
  a thumbnail.

  Deliberately renders only the one relevant section, not the whole
  homepage: the editor doesn't need `courses`/`mentors` data just to preview
  an image slot, and a full-page embed is exactly the cluttered, always-on
  replica the admin editor was simplified away from (see the module doc on
  `WasomiWeb.AdminLive.LandingImages`).
  """

  use Phoenix.Component

  import WasomiWeb.HomeComponents, only: [hero: 1, gs1_in_action: 1]

  alias Phoenix.HTML.Safe

  @step_index %{
    gs1_step_identify: 1,
    gs1_step_capture: 2,
    gs1_step_share: 3,
    gs1_step_verify: 4
  }

  @doc """
  A standalone HTML document (fonts + the site's compiled CSS linked)
  containing the real section `slot` belongs to, suitable for an iframe
  `srcdoc`. `images` is the same `%{slot => %{url:, alt:}}` shape as
  `Wasomi.Content.landing_image_map/0` — pass in whatever should currently
  render for each slot (a not-yet-saved upload's URL for the one being
  edited, its persisted/default value otherwise).
  """
  def render_html(:hero, images) do
    render_document(hero(%{images: images}), hero_carousel_script())
  end

  def render_html(slot, images) do
    step = Map.fetch!(@step_index, slot)
    render_document(gs1_in_action(%{images: images}), select_step_script(step))
  end

  defp render_document(section, extra_script) do
    section_html = section |> Safe.to_iodata() |> IO.iodata_to_binary()
    document(section_html, extra_script <> image_retry_script())
  end

  # A freshly-uploaded R2 object can briefly 404 while it propagates through
  # R2/the CDN in front of it — the same lag `Hooks.ImageRetry` and
  # `Hooks.LiveImagePreview` already retry around elsewhere in the admin
  # editor. Those are Phoenix hooks, though, and there's no LiveSocket
  # running inside this `srcdoc` document to attach one to — so this is the
  # same retry-with-backoff idea as plain, self-contained JS instead.
  # Phoenix hooks don't run inside a `srcdoc` document, so mirror the real
  # homepage's `Hooks.HeroCarousel` as plain JS (faster interval). No-op for ≤1 image.
  defp hero_carousel_script do
    """
    <script>
      (function () {
        var root = document.getElementById("hero-carousel");
        if (!root) return;
        var slides = Array.prototype.slice.call(root.querySelectorAll("[data-hero-slide]"));
        var dots = Array.prototype.slice.call(root.querySelectorAll("[data-hero-dot]"));
        if (slides.length < 2) return;
        var active = 0;
        function goTo(i) {
          var next = ((i % slides.length) + slides.length) % slides.length;
          if (next === active) return;
          slides[active].classList.replace("opacity-100", "opacity-0");
          slides[next].classList.replace("opacity-0", "opacity-100");
          if (dots[active]) {
            dots[active].classList.replace("w-6", "w-2");
            dots[active].classList.replace("bg-white", "bg-white/40");
          }
          if (dots[next]) {
            dots[next].classList.replace("w-2", "w-6");
            dots[next].classList.replace("bg-white/40", "bg-white");
          }
          active = next;
        }
        slides[0].classList.remove("animate-image-in");
        dots.forEach(function (dot, i) {
          dot.addEventListener("click", function () { goTo(i); });
        });
        setInterval(function () { goTo(active + 1); }, 3000);
      })();
    </script>
    """
  end

  defp image_retry_script do
    """
    <script>
      document.querySelectorAll("img").forEach(function (img) {
        var attempts = 0;
        img.addEventListener("error", function () {
          if (attempts >= 5) return;
          attempts += 1;
          var src = img.src;
          setTimeout(function () {
            img.src = "";
            img.src = src;
          }, 300 * attempts);
        });
      });
    </script>
    """
  end

  # The compiled stylesheet is inlined rather than `<link>`ed: its first
  # line is `@import url(https://fonts.googleapis.com/...)`, and an
  # `@import` is render-blocking for the *whole* stylesheet, not just the
  # font — so a slow/unreachable font request stalls every local Tailwind
  # rule right along with it, leaving the preview blank however long the
  # network fetch takes. Stripping just that line keeps the preview fully
  # self-contained and network-independent; it falls back to a generic
  # sans-serif (see `document/1`) instead of the real Outfit font, which is
  # a fine trade for an internal preview panel — the real published page
  # still links `app.css` normally and gets the real font.
  #
  # Cached in `:persistent_term`: this renders on every keystroke/upload
  # tick while the edit modal is open, and re-reading + re-regexing a
  # ~170 KB file from disk each time isn't free. `app.css` only changes on
  # a fresh deploy (new BEAM instance), so there's nothing to invalidate.
  #
  # `app.css` is a build artifact from `mix assets.build`/`assets.deploy`,
  # not something `mix compile`/`mix test` produces on their own — CI's
  # test job never runs it, so the file legitimately doesn't exist there.
  # Falling back to "" (unstyled but functional) instead of raising keeps
  # this page's tests, and any fresh checkout, working without that step.
  defp css do
    :persistent_term.get({__MODULE__, :css}, nil) || load_and_cache_css()
  end

  defp load_and_cache_css do
    css =
      case Application.app_dir(:wasomi, "priv/static/assets/app.css") |> File.read() do
        {:ok, contents} ->
          # `[^;]+` would stop at the first `;` — but the font URL itself
          # has several (`wght@400;500;600;...`), so match the whole line.
          String.replace(contents, ~r/^@import.*\n/, "", global: false)

        {:error, _reason} ->
          ""
      end

    :persistent_term.put({__MODULE__, :css}, css)
    css
  end

  # Step 1 is already the markup's default `checked` radio — nothing to do.
  defp select_step_script(1), do: ""

  defp select_step_script(step) do
    """
    <script>
      var radio = document.getElementById("gs1-step-#{step}");
      if (radio) radio.checked = true;
    </script>
    """
  end

  # A plain string, not `~H`: HEEx doesn't evaluate `{...}` interpolation
  # inside `<style>`/`<script>` tag bodies (the tokenizer treats them as raw
  # text, per the HTML spec), so embedding the CSS/section/script blocks
  # that way silently prints the literal `{...}` source instead of running
  # it. `section_html`/`extra_script` are already-safe rendered strings by
  # the time they get here.
  defp document(section_html, extra_script) do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <style>
          body { margin: 0; font-family: ui-sans-serif, system-ui, sans-serif; }
        </style>
        <style>#{css()}</style>
      </head>
      <body>
        #{section_html}
        #{extra_script}
      </body>
    </html>
    """
  end
end
