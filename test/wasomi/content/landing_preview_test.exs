defmodule Wasomi.Content.LandingPreviewTest do
  use ExUnit.Case, async: true

  alias Wasomi.Content.LandingImage
  alias Wasomi.Content.LandingPreview

  defp images do
    LandingImage.slots()
    |> Map.new(fn slot ->
      {slot, %{url: LandingImage.default_path(slot), alt: LandingImage.default_alt(slot)}}
    end)
    |> Map.update!(:hero, &[&1])
  end

  test "renders a standalone document with the hero image for the hero slot" do
    html = LandingPreview.render_html(:hero, images())

    assert html =~ "<!doctype html>"
    refute html =~ "fonts.googleapis.com"
    assert html =~ LandingImage.default_path(:hero)
  end

  # `app.css` is a build artifact (`mix assets.build`/`assets.deploy`), not
  # something `mix test` produces on its own — CI's test job never runs it,
  # so this can't assume the file exists. When it's present locally this
  # also happens to prove the stylesheet actually got inlined.
  test "inlines the compiled stylesheet when it has been built" do
    css_path = Application.app_dir(:wasomi, "priv/static/assets/app.css")

    if File.exists?(css_path) do
      assert LandingPreview.render_html(:hero, images()) =~ "tailwindcss"
    end
  end

  test "a not-yet-saved override URL is reflected in the rendered document" do
    images = Map.put(images(), :hero, [%{url: "https://cdn.example.test/pending.png", alt: ""}])

    html = LandingPreview.render_html(:hero, images)

    assert html =~ "https://cdn.example.test/pending.png"
  end

  test "renders the GS1-in-action section with all four step images for a step slot" do
    html = LandingPreview.render_html(:gs1_step_share, images())

    for slot <- [
          :gs1_step_identify,
          :gs1_step_capture,
          :gs1_step_share,
          :gs1_step_verify
        ] do
      assert html =~ LandingImage.default_path(slot)
    end
  end

  test "a step slot other than the first ships a script selecting its radio button" do
    assert LandingPreview.render_html(:gs1_step_capture, images()) =~ "gs1-step-2"

    refute LandingPreview.render_html(:gs1_step_identify, images()) =~
             "getElementById(\"gs1-step-"
  end

  test "every rendered document retries a broken image, for freshly-uploaded R2 objects still propagating" do
    for slot <- [:hero, :gs1_step_identify] do
      assert LandingPreview.render_html(slot, images()) =~ "addEventListener(\"error\""
    end
  end
end
