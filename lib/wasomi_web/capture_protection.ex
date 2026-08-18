defmodule WasomiWeb.CaptureProtection do
  @moduledoc """
  Marks a surface as protected course content.

  There is no browser API that can stop an OS screenshot or a screen recorder,
  so nothing here claims to. What it does is the two things the web actually
  allows:

    * **Deterrence** — `Hooks.CaptureGuard` (assets/js/app.js) blocks the cheap
      copy routes (right-click, drag, Ctrl/Cmd+C, Ctrl/Cmd+P, Ctrl/Cmd+S), the
      video player refuses picture-in-picture, AirPlay and its own download
      button, playback pauses and veils when the tab goes to the background,
      and printing is replaced with a notice (`@media print` in app.css).
    * **Traceability** — every guarded surface is tiled with the viewer's
      internal account id, so a capture that does get out is attributable to
      one account without exposing the viewer's email address.

  Real prevention for video needs hardware DRM (Widevine L1 / PlayReady
  SL3000 / FairPlay), which makes the OS compositor black out the video surface
  in captures. Cloudflare Stream — our provider, see `Wasomi.Media.Cloudflare` —
  does not offer it, so it is not available to us today. Downloadable resources
  (`WasomiWeb.ResourceController`) are outside this by definition: a learner who
  can download a PDF has the file.

  Spread onto the element wrapping the protected content:

      <div {capture_guard_attrs(@current_user)}>

  The hook adds the `capture-guarded` class itself on mount, which is what the
  CSS half keys off — so a client with JS disabled gets no guard, which is fine:
  it also gets no player.
  """

  @doc """
  Hook + identity attributes for the wrapper around protected content.
  """
  def capture_guard_attrs(user) do
    %{"phx-hook" => "CaptureGuard", "data-watermark" => watermark_text(user)}
  end

  @doc """
  The non-sensitive account identifier stamped across guarded pixels.

  The id keeps a leak attributable and survives an email change without
  exposing personally identifiable contact information in the page background.
  """
  def watermark_text(user), do: "User ##{user.id}"
end
