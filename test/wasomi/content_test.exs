defmodule Wasomi.ContentTest do
  use Wasomi.DataCase

  alias Wasomi.Content
  alias Wasomi.Content.LandingImage

  # A representative single-image slot for exercising the generic
  # put/reset/list functions — anything but :hero, which is the one
  # multi-image slot and has its own describe block below.
  @slot :gs1_step_identify

  describe "landing_image_map/0" do
    test "falls back to the hardcoded default url/alt for every slot with no override" do
      map = Content.landing_image_map()

      assert map == %{
               hero: [%{url: "/images/hero-home.png", alt: ""}],
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
      {:ok, _} = Content.put_landing_image(@slot, "https://cdn.example.test/img.png", "Custom")

      map = Content.landing_image_map()

      assert map[@slot] == %{url: "https://cdn.example.test/img.png", alt: "Custom"}
      assert map.gs1_step_capture.url == LandingImage.default_path(:gs1_step_capture)
    end

    test "falls back to the slot's default alt text when an override has no alt text set" do
      {:ok, _} = Content.put_landing_image(@slot, "https://cdn.example.test/img.png")

      assert Content.landing_image_map()[@slot].alt == LandingImage.default_alt(@slot)
    end

    test "hero resolves to every override image, in position order" do
      {:ok, _} = Content.add_hero_image("https://cdn.example.test/1.png", "First")
      {:ok, _} = Content.add_hero_image("https://cdn.example.test/2.png", "Second")

      assert Content.landing_image_map().hero == [
               %{url: "https://cdn.example.test/1.png", alt: "First"},
               %{url: "https://cdn.example.test/2.png", alt: "Second"}
             ]
    end
  end

  describe "image_url_for/1" do
    test "returns the default when no override exists" do
      assert Content.image_url_for(@slot) == LandingImage.default_path(@slot)
    end

    test "returns the override once one is set" do
      {:ok, _} = Content.put_landing_image(@slot, "https://cdn.example.test/img.png")

      assert Content.image_url_for(@slot) == "https://cdn.example.test/img.png"
    end

    test "raises for a slot outside the fixed set" do
      assert_raise MatchError, fn -> Content.image_url_for(:not_a_real_slot) end
    end
  end

  describe "list_landing_image_slots/0" do
    test "lists every single-image slot with its label, default, resolved image and override flag, excluding hero" do
      slots = Content.list_landing_image_slots()

      assert length(slots) == length(LandingImage.slots()) - 1
      refute Enum.any?(slots, &(&1.slot == :hero))

      slot = Enum.find(slots, &(&1.slot == @slot))
      assert slot.label == LandingImage.label(@slot)
      assert slot.default_path == LandingImage.default_path(@slot)
      assert slot.image_url == LandingImage.default_path(@slot)
      assert slot.alt_text == LandingImage.default_alt(@slot)
      refute slot.overridden?
    end

    test "marks an overridden slot and resolves its override as the image_url" do
      {:ok, _} = Content.put_landing_image(@slot, "https://cdn.example.test/img.png")

      slot =
        Content.list_landing_image_slots()
        |> Enum.find(&(&1.slot == @slot))

      assert slot.overridden?
      assert slot.image_url == "https://cdn.example.test/img.png"
    end
  end

  describe "put_landing_image/2" do
    test "creates an override for a slot with none yet" do
      assert {:ok, %LandingImage{slot: @slot, image_url: url}} =
               Content.put_landing_image(@slot, "https://cdn.example.test/img.png")

      assert url == "https://cdn.example.test/img.png"
    end

    test "accepts an optional alt_text override" do
      assert {:ok, %LandingImage{alt_text: "Custom shot"}} =
               Content.put_landing_image(
                 @slot,
                 "https://cdn.example.test/img.png",
                 "Custom shot"
               )
    end

    test "alt_text defaults to nil when omitted" do
      assert {:ok, %LandingImage{alt_text: nil}} =
               Content.put_landing_image(@slot, "https://cdn.example.test/img.png")
    end

    test "replaces an existing override for the same slot instead of duplicating it" do
      {:ok, _} = Content.put_landing_image(@slot, "https://cdn.example.test/first.png")
      {:ok, _} = Content.put_landing_image(@slot, "https://cdn.example.test/second.png")

      assert Content.image_url_for(@slot) == "https://cdn.example.test/second.png"
      assert Repo.aggregate(LandingImage, :count) == 1
    end

    test "rejects a slot outside the fixed set" do
      assert {:error, changeset} =
               Content.put_landing_image(:not_a_real_slot, "https://x.test/y.png")

      assert %{slot: ["is invalid"]} = errors_on(changeset)
    end

    test "requires a non-blank image_url" do
      assert {:error, changeset} = Content.put_landing_image(@slot, nil)
      assert %{image_url: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "reset_landing_image/1" do
    test "clears an existing override back to the default" do
      {:ok, _} = Content.put_landing_image(@slot, "https://cdn.example.test/img.png")

      assert :ok = Content.reset_landing_image(@slot)
      assert Content.image_url_for(@slot) == LandingImage.default_path(@slot)
    end

    test "is a no-op for a slot with no override" do
      assert :ok = Content.reset_landing_image(@slot)
      assert Content.image_url_for(@slot) == LandingImage.default_path(@slot)
    end
  end

  describe "hero images" do
    test "list_hero_images/0 is empty with no overrides" do
      assert Content.list_hero_images() == []
    end

    test "add_hero_image/2 appends in order, at consecutive positions" do
      {:ok, a} = Content.add_hero_image("https://cdn.example.test/1.png", "First")
      {:ok, b} = Content.add_hero_image("https://cdn.example.test/2.png")

      assert [img_a, img_b] = Content.list_hero_images()
      assert img_a == %{id: a.id, url: a.image_url, alt: "First", position: 0}
      assert img_b == %{id: b.id, url: b.image_url, alt: nil, position: 1}
    end

    test "add_hero_image/2 refuses past the cap" do
      for n <- 1..LandingImage.multi_slot_max() do
        assert {:ok, _} = Content.add_hero_image("https://cdn.example.test/#{n}.png")
      end

      assert Content.add_hero_image("https://cdn.example.test/over.png") ==
               {:error, :limit_reached}

      assert length(Content.list_hero_images()) == LandingImage.multi_slot_max()
    end

    test "remove_hero_image/1 deletes the image and closes the position gap" do
      {:ok, a} = Content.add_hero_image("https://cdn.example.test/1.png")
      {:ok, b} = Content.add_hero_image("https://cdn.example.test/2.png")
      {:ok, c} = Content.add_hero_image("https://cdn.example.test/3.png")

      assert {:ok, :ok} = Content.remove_hero_image(a.id)

      assert [img_b, img_c] = Content.list_hero_images()
      assert img_b.id == b.id and img_b.position == 0
      assert img_c.id == c.id and img_c.position == 1
    end

    test "remove_hero_image/1 errors for an id that isn't a hero image" do
      {:ok, single} = Content.put_landing_image(@slot, "https://cdn.example.test/img.png")

      assert {:error, :not_found} = Content.remove_hero_image(single.id)
      assert {:error, :not_found} = Content.remove_hero_image(-1)
    end

    test "move_hero_image/2 swaps with the neighbor in the given direction" do
      {:ok, a} = Content.add_hero_image("https://cdn.example.test/1.png")
      {:ok, b} = Content.add_hero_image("https://cdn.example.test/2.png")

      assert :ok = Content.move_hero_image(b.id, :up)

      assert [first, second] = Content.list_hero_images()
      assert first.id == b.id
      assert second.id == a.id
    end

    test "move_hero_image/2 is a no-op at either end of the list" do
      {:ok, a} = Content.add_hero_image("https://cdn.example.test/1.png")
      {:ok, b} = Content.add_hero_image("https://cdn.example.test/2.png")

      assert :ok = Content.move_hero_image(a.id, :up)
      assert :ok = Content.move_hero_image(b.id, :down)

      assert [first, second] = Content.list_hero_images()
      assert first.id == a.id
      assert second.id == b.id
    end
  end
end
