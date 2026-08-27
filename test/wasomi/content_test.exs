defmodule Wasomi.ContentTest do
  use Wasomi.DataCase

  alias Wasomi.Content
  alias Wasomi.Content.LandingImage

  describe "landing_image_map/0" do
    test "falls back to the hardcoded default url/alt for every slot with no override" do
      map = Content.landing_image_map()

      assert map == %{
               hero: %{url: "/images/hero-home.png", alt: ""},
               gs1_step_identify: %{
                 url: "/images/gs1-box.png",
                 alt: "Product labelled with a GS1 barcode"
               },
               gs1_step_capture: %{
                 url: "/images/hero-home.png",
                 alt: "Scanning a barcode to capture product data"
               },
               gs1_step_share: %{
                 url: "/images/hero_image.jpg",
                 alt: "Trading partners sharing product data"
               },
               gs1_step_verify: %{
                 url: "/images/auth-learning-bg.jpg",
                 alt: "Verifying a product along its journey"
               }
             }
    end

    test "uses the override for an overridden slot, defaults for the rest" do
      {:ok, _} =
        Content.put_landing_image(:hero, "https://cdn.example.test/hero.png", "Custom hero")

      map = Content.landing_image_map()

      assert map.hero == %{url: "https://cdn.example.test/hero.png", alt: "Custom hero"}
      assert map.gs1_step_identify.url == LandingImage.default_path(:gs1_step_identify)
    end

    test "falls back to the slot's default alt text when an override has no alt text set" do
      {:ok, _} = Content.put_landing_image(:hero, "https://cdn.example.test/hero.png")

      assert Content.landing_image_map().hero.alt == LandingImage.default_alt(:hero)
    end
  end

  describe "image_url_for/1" do
    test "returns the default when no override exists" do
      assert Content.image_url_for(:hero) == LandingImage.default_path(:hero)
    end

    test "returns the override once one is set" do
      {:ok, _} = Content.put_landing_image(:hero, "https://cdn.example.test/hero.png")

      assert Content.image_url_for(:hero) == "https://cdn.example.test/hero.png"
    end

    test "raises for a slot outside the fixed set" do
      assert_raise MatchError, fn -> Content.image_url_for(:not_a_real_slot) end
    end
  end

  describe "list_landing_image_slots/0" do
    test "lists every slot with its label, default, resolved image and override flag" do
      slots = Content.list_landing_image_slots()

      assert length(slots) == length(LandingImage.slots())

      hero = Enum.find(slots, &(&1.slot == :hero))
      assert hero.label == LandingImage.label(:hero)
      assert hero.default_path == LandingImage.default_path(:hero)
      assert hero.image_url == LandingImage.default_path(:hero)
      assert hero.alt_text == LandingImage.default_alt(:hero)
      refute hero.overridden?
    end

    test "marks an overridden slot and resolves its override as the image_url" do
      {:ok, _} = Content.put_landing_image(:hero, "https://cdn.example.test/hero.png")

      hero =
        Content.list_landing_image_slots()
        |> Enum.find(&(&1.slot == :hero))

      assert hero.overridden?
      assert hero.image_url == "https://cdn.example.test/hero.png"
    end
  end

  describe "put_landing_image/2" do
    test "creates an override for a slot with none yet" do
      assert {:ok, %LandingImage{slot: :hero, image_url: url}} =
               Content.put_landing_image(:hero, "https://cdn.example.test/hero.png")

      assert url == "https://cdn.example.test/hero.png"
    end

    test "accepts an optional alt_text override" do
      assert {:ok, %LandingImage{alt_text: "Custom hero shot"}} =
               Content.put_landing_image(
                 :hero,
                 "https://cdn.example.test/hero.png",
                 "Custom hero shot"
               )
    end

    test "alt_text defaults to nil when omitted" do
      assert {:ok, %LandingImage{alt_text: nil}} =
               Content.put_landing_image(:hero, "https://cdn.example.test/hero.png")
    end

    test "replaces an existing override for the same slot instead of duplicating it" do
      {:ok, _} = Content.put_landing_image(:hero, "https://cdn.example.test/first.png")
      {:ok, _} = Content.put_landing_image(:hero, "https://cdn.example.test/second.png")

      assert Content.image_url_for(:hero) == "https://cdn.example.test/second.png"
      assert Repo.aggregate(LandingImage, :count) == 1
    end

    test "rejects a slot outside the fixed set" do
      assert {:error, changeset} =
               Content.put_landing_image(:not_a_real_slot, "https://x.test/y.png")

      assert %{slot: ["is invalid"]} = errors_on(changeset)
    end

    test "requires a non-blank image_url" do
      assert {:error, changeset} = Content.put_landing_image(:hero, nil)
      assert %{image_url: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "reset_landing_image/1" do
    test "clears an existing override back to the default" do
      {:ok, _} = Content.put_landing_image(:hero, "https://cdn.example.test/hero.png")

      assert :ok = Content.reset_landing_image(:hero)
      assert Content.image_url_for(:hero) == LandingImage.default_path(:hero)
    end

    test "is a no-op for a slot with no override" do
      assert :ok = Content.reset_landing_image(:hero)
      assert Content.image_url_for(:hero) == LandingImage.default_path(:hero)
    end
  end
end
