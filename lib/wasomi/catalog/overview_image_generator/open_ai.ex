defmodule Wasomi.Catalog.OverviewImageGenerator.OpenAI do
  @moduledoc """
  Generates a scene's background illustration via OpenAI's
  `/images/generations` endpoint (`gpt-image-1`) — same request/error shape
  as the other OpenAI adapters in this app (`OverviewNarrator.OpenAI`,
  `OverviewScriptGenerator.OpenAI`), speaking the API directly over `Req`
  rather than an SDK (none exists for Elixir).

  `gpt-image-1` always returns base64-encoded image data (`b64_json`), not
  a URL, so there's no separate download step.
  """

  @behaviour Wasomi.Catalog.OverviewImageGenerator

  @api_url "https://api.openai.com/v1/images/generations"
  @default_model "gpt-image-1"
  # Closest supported landscape size to this app's 1280x720 slide frame —
  # `Wasomi.Catalog.SlideRenderer.ChromicPdf` crops it to fit via CSS
  # `background-size: cover`, so an exact pixel match isn't required.
  @size "1536x1024"

  @impl true
  def generate(scene_text, _opts \\ []) when is_binary(scene_text) do
    body = %{
      "model" => model(),
      "prompt" => illustration_prompt(scene_text),
      "size" => @size,
      "quality" => "high",
      "n" => 1
    }

    with {:ok, api_key} <- api_key() do
      response =
        Req.post(@api_url,
          json: body,
          headers: [
            {"Content-Type", "application/json"},
            {"Authorization", "Bearer #{api_key}"}
          ],
          retry: :transient,
          max_retries: 5,
          receive_timeout: 120_000
        )

      case response do
        {:ok, %{status: 200, body: %{"data" => [%{"b64_json" => b64} | _]}}} ->
          decode_image(b64)

        {:ok, %{status: 200, body: body}} ->
          {:error, {:unexpected_response, body}}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp decode_image(b64) do
    case Base.decode64(b64) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :invalid_base64_image}
    end
  end

  # A realistic-photo version of this prompt was tried and reverted — it
  # produced generic, loosely-related stock-photo scenes (the same couple
  # of stock images reused across very different scenes) that were less
  # tied to the source material than the flat-illustration style this
  # reverts to. Explicitly requiring a human character performing the
  # *specific* action in `scene_text` (not just an object/prop shot) is
  # what actually grounds the image in that scene, not the art style.
  defp illustration_prompt(scene_text) do
    """
    A flat, modern vector-style illustration for an educational video
    slide, depicting a person actively doing this specific thing, drawn
    directly from this exact moment in the material: #{scene_text}

    The illustration must depict this specific action or idea clearly and
    literally — avoid a generic, decorative, or loosely-related stand-in
    scene. Center the illustration on an illustrated human character
    performing the action described, not just objects, icons, or props
    alone. Vary the character's skin tone across generations, weighted
    mostly toward Black/dark skin tones.

    Style: flat, modern vector illustration (in the style of contemporary
    tech/education illustration sets) — clean shapes, bold flat colors,
    minimal shading. Not a photograph, not a 3D render, not generic clip
    art. No text, no letters, no words, no captions, no labels, no logos
    anywhere in the image.
    """
  end

  defp api_key do
    case Application.get_env(:wasomi, :openai_api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :openai_api_key_not_configured}
    end
  end

  defp model, do: Application.get_env(:wasomi, :openai_image_model, @default_model)
end
