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
end
