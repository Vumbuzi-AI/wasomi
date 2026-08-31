defmodule Wasomi.ContentFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Wasomi.Content` context.
  """

  @doc """
  Sets a landing image override for `slot` directly (bypassing the admin
  LiveView/upload flow), for tests that only care about the resolved value.
  """
  def landing_image_fixture(slot, image_url \\ "https://cdn.example.test/override.png") do
    {:ok, landing_image} = Wasomi.Content.put_landing_image(slot, image_url)
    landing_image
  end

  @doc "Appends a hero image directly, bypassing the admin upload flow."
  def hero_image_fixture(image_url \\ "https://cdn.example.test/hero.png", alt_text \\ nil) do
    {:ok, landing_image} = Wasomi.Content.add_hero_image(image_url, alt_text)
    landing_image
  end
end
