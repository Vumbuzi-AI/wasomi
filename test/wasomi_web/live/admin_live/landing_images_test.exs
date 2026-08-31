defmodule WasomiWeb.AdminLive.LandingImagesTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.ContentFixtures

  alias Wasomi.Content
  alias Wasomi.Content.LandingImage

  # A representative single-image slot — anything but :hero, which has its
  # own describe block below.
  @slot :gs1_step_identify

  defp escape_html(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp admin_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  test "renders every defined slot with its label and default image", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/landing-images")

    assert html =~ "Hero banner"
    assert html =~ "See GS1 in action"

    for slot <- LandingImage.slots() do
      assert html =~ escape_html(LandingImage.label(slot))
      assert html =~ LandingImage.default_path(slot)
    end
  end

  test "learners and unauthenticated visitors cannot reach the page", %{conn: conn} do
    learner = user_fixture()

    assert {:error, {:redirect, _}} =
             conn
             |> log_in_user(learner)
             |> live(~p"/admin/landing-images")

    assert {:error, {:redirect, _}} = live(build_conn(), ~p"/admin/landing-images")
  end

  describe "a single-image slot" do
    test "shows an overridden slot's custom image and status on its card", %{conn: conn} do
      landing_image_fixture(@slot, "https://cdn.example.test/override.png")

      {:ok, _view, html} = live(conn, ~p"/admin/landing-images")

      assert html =~ "https://cdn.example.test/override.png"
      assert html =~ "Custom"
    end

    test "clicking edit opens the slot configuration modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/landing-images")

      refute has_element?(view, "#edit-slot-modal")

      html =
        view
        |> element("#edit-slot-#{@slot}-btn")
        |> render_click()

      assert has_element?(view, "#edit-slot-modal")
      assert html =~ escape_html(LandingImage.label(@slot))
      assert html =~ "Upload new image"
    end

    test "uploading a PNG and saving sets the slot's override and updates live preview", %{
      conn: conn
    } do
      with_landing_image_storage_mock(fn ->
        {:ok, view, _html} = live(conn, ~p"/admin/landing-images")

        view
        |> element("#edit-slot-#{@slot}-btn")
        |> render_click()

        upload =
          file_input(view, "#landing-image-#{@slot}", @slot, [
            %{name: "img.png", content: "fake-png-bytes", type: "image/png"}
          ])

        html = render_upload(upload, "img.png")
        assert html =~ "https://cdn.example.test/landing/#{@slot}/img.png"

        view
        |> element("#landing-image-#{@slot}")
        |> render_submit(%{"slot" => "#{@slot}"})

        assert Content.image_url_for(@slot) == "https://cdn.example.test/landing/#{@slot}/img.png"
        # The slot's description isn't admin-editable; it uses the slot default.
        assert Content.landing_image_map()[@slot].alt == LandingImage.default_alt(@slot)
      end)
    end

    test "saving without picking a new image just closes the modal, leaving the override intact",
         %{conn: conn} do
      landing_image_fixture(@slot, "https://cdn.example.test/override.png")

      {:ok, view, _html} = live(conn, ~p"/admin/landing-images")

      view
      |> element("#edit-slot-#{@slot}-btn")
      |> render_click()

      view
      |> element("#landing-image-#{@slot}")
      |> render_submit(%{"slot" => "#{@slot}"})

      refute has_element?(view, "#edit-slot-modal")
      assert Content.image_url_for(@slot) == "https://cdn.example.test/override.png"
    end

    test "resetting an overridden slot clears it back to the default", %{conn: conn} do
      landing_image_fixture(@slot, "https://cdn.example.test/override.png")

      {:ok, view, html} = live(conn, ~p"/admin/landing-images")
      assert html =~ "https://cdn.example.test/override.png"

      view
      |> element("#edit-slot-#{@slot}-btn")
      |> render_click()

      html =
        view
        |> element("button[phx-click='reset'][phx-value-slot='#{@slot}']")
        |> render_click()

      refute html =~ "https://cdn.example.test/override.png"
      assert html =~ LandingImage.default_path(@slot)
      assert Content.image_url_for(@slot) == LandingImage.default_path(@slot)
    end

    test "an upload with no public URL configured flashes an error instead of silently dropping it",
         %{conn: conn} do
      with_no_public_url_storage_mock(fn ->
        {:ok, view, _html} = live(conn, ~p"/admin/landing-images")

        view
        |> element("#edit-slot-#{@slot}-btn")
        |> render_click()

        upload =
          file_input(view, "#landing-image-#{@slot}", @slot, [
            %{name: "img.png", content: "fake-png-bytes", type: "image/png"}
          ])

        render_upload(upload, "img.png")

        html =
          view
          |> element("#landing-image-#{@slot}")
          |> render_submit(%{"slot" => "#{@slot}"})

        assert html =~ "R2_PUBLIC_URL"
        refute Content.image_url_for(@slot) == "https://cdn.example.test/landing/#{@slot}/img.png"
      end)
    end
  end

  describe "the hero slot" do
    test "shows 'Default' with no overrides and 'Custom (N)' once images are added", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, ~p"/admin/landing-images")
      assert html =~ "Default"

      hero_image_fixture()
      hero_image_fixture("https://cdn.example.test/hero2.png")

      {:ok, _view, html} = live(conn, ~p"/admin/landing-images")
      assert html =~ "Custom (2)"
    end

    test "clicking edit opens the hero list-management modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/landing-images")

      refute has_element?(view, "#edit-hero-modal")

      html =
        view
        |> element("#edit-slot-hero-btn")
        |> render_click()

      assert has_element?(view, "#edit-hero-modal")
      assert html =~ "Hero banner"
      assert html =~ "Add an image"
      assert html =~ "No custom hero images yet"
    end

    test "uploading a PNG appends it immediately, no separate save step", %{conn: conn} do
      with_landing_image_storage_mock(fn ->
        {:ok, view, _html} = live(conn, ~p"/admin/landing-images")

        view
        |> element("#edit-slot-hero-btn")
        |> render_click()

        upload =
          file_input(view, "#landing-image-hero", :hero, [
            %{name: "hero.png", content: "fake-png-bytes", type: "image/png"}
          ])

        html = render_upload(upload, "hero.png")

        assert html =~ "https://cdn.example.test/landing/hero/hero.png"

        assert [%{url: "https://cdn.example.test/landing/hero/hero.png"}] =
                 Content.list_hero_images()
      end)
    end

    test "removing an image takes it out of the list", %{conn: conn} do
      image = hero_image_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/landing-images")

      view
      |> element("#edit-slot-hero-btn")
      |> render_click()

      html =
        view
        |> element("button[phx-click='remove-hero-image'][phx-value-id='#{image.id}']")
        |> render_click()

      assert html =~ "No custom hero images yet"
      assert Content.list_hero_images() == []
    end

    test "moving an image changes its order", %{conn: conn} do
      first = hero_image_fixture("https://cdn.example.test/1.png")
      second = hero_image_fixture("https://cdn.example.test/2.png")

      {:ok, view, _html} = live(conn, ~p"/admin/landing-images")

      view
      |> element("#edit-slot-hero-btn")
      |> render_click()

      view
      |> element(
        "button[phx-click='move-hero-image'][phx-value-id='#{second.id}'][phx-value-direction='up']"
      )
      |> render_click()

      assert [%{id: id1}, %{id: id2}] = Content.list_hero_images()
      assert id1 == second.id
      assert id2 == first.id
    end

    test "the upload control disappears once the cap is reached", %{conn: conn} do
      for n <- 1..LandingImage.multi_slot_max() do
        hero_image_fixture("https://cdn.example.test/#{n}.png")
      end

      {:ok, view, _html} = live(conn, ~p"/admin/landing-images")

      html =
        view
        |> element("#edit-slot-hero-btn")
        |> render_click()

      assert html =~ "Custom (5)"
      refute has_element?(view, "#edit-hero-modal form")
    end

    test "an upload with no public URL configured flashes an error and isn't added", %{
      conn: conn
    } do
      with_no_public_url_storage_mock(fn ->
        {:ok, view, _html} = live(conn, ~p"/admin/landing-images")

        view
        |> element("#edit-slot-hero-btn")
        |> render_click()

        upload =
          file_input(view, "#landing-image-hero", :hero, [
            %{name: "hero.png", content: "fake-png-bytes", type: "image/png"}
          ])

        html = render_upload(upload, "hero.png")

        assert html =~ "R2_PUBLIC_URL"
        assert Content.list_hero_images() == []
      end)
    end
  end

  defp with_landing_image_storage_mock(fun) do
    previous_provider = Application.get_env(:wasomi, :storage_provider)
    previous_public_url = Application.get_env(:wasomi, :r2_public_url)

    Application.put_env(:wasomi, :storage_provider, __MODULE__.LandingImageStorageMock)
    Application.put_env(:wasomi, :r2_public_url, "https://cdn.example.test")

    try do
      fun.()
    after
      Application.put_env(:wasomi, :storage_provider, previous_provider)
      Application.put_env(:wasomi, :r2_public_url, previous_public_url)
    end
  end

  defp with_no_public_url_storage_mock(fun) do
    previous_provider = Application.get_env(:wasomi, :storage_provider)
    Application.put_env(:wasomi, :storage_provider, __MODULE__.NoPublicUrlStorageMock)

    try do
      fun.()
    after
      Application.put_env(:wasomi, :storage_provider, previous_provider)
    end
  end

  defmodule LandingImageStorageMock do
    def presign_upload(_user, attrs) do
      prefix = Map.fetch!(attrs, "prefix")
      filename = Map.fetch!(attrs, "filename")

      {:ok,
       %{
         url: "https://r2.example.test/presigned-url",
         key: "#{prefix}/#{filename}",
         public_url: "https://cdn.example.test/#{prefix}/#{filename}",
         content_type: "image/png"
       }}
    end
  end

  defmodule NoPublicUrlStorageMock do
    def presign_upload(_user, _attrs) do
      {:ok,
       %{
         url: "https://r2.example.test/presigned-url",
         key: "landing/hero/hero.png",
         public_url: nil,
         content_type: "image/png"
       }}
    end
  end
end
