defmodule WasomiWeb.AdminLive.LandingImagesTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.ContentFixtures

  alias Wasomi.Content
  alias Wasomi.Content.LandingImage

  defp escape_html(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp admin_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  test "renders every defined slot with its label and default image in live preview", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, ~p"/admin/landing-images")

    assert html =~ "Hero banner"
    assert html =~ "See GS1 in action"

    for slot <- LandingImage.slots() do
      assert html =~ escape_html(LandingImage.label(slot))
      assert html =~ LandingImage.default_path(slot)
    end
  end

  test "shows an overridden slot's custom image and status on its card", %{conn: conn} do
    landing_image_fixture(:hero, "https://cdn.example.test/hero.png")

    {:ok, _view, html} = live(conn, ~p"/admin/landing-images")

    assert html =~ "https://cdn.example.test/hero.png"
    assert html =~ "Custom"
  end

  test "learners and unauthenticated visitors cannot reach the page", %{conn: conn} do
    learner = user_fixture()

    assert {:error, {:redirect, _}} =
             conn
             |> log_in_user(learner)
             |> live(~p"/admin/landing-images")

    assert {:error, {:redirect, _}} = live(build_conn(), ~p"/admin/landing-images")
  end

  test "clicking edit opens the slot configuration modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/landing-images")

    refute has_element?(view, "#edit-slot-modal")

    html =
      view
      |> element("#edit-slot-hero-btn")
      |> render_click()

    assert has_element?(view, "#edit-slot-modal")
    assert html =~ "Hero banner"
    assert html =~ "Upload new PNG image"
  end

  test "uploading a PNG and saving sets the slot's override and updates live preview", %{
    conn: conn
  } do
    previous_provider = Application.get_env(:wasomi, :storage_provider)
    previous_public_url = Application.get_env(:wasomi, :r2_public_url)

    on_exit(fn ->
      Application.put_env(:wasomi, :storage_provider, previous_provider)
      Application.put_env(:wasomi, :r2_public_url, previous_public_url)
    end)

    Application.put_env(:wasomi, :storage_provider, __MODULE__.LandingImageStorageMock)
    Application.put_env(:wasomi, :r2_public_url, "https://cdn.example.test")

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

    view
    |> element("#landing-image-hero")
    |> render_submit(%{"slot" => "hero", "alt_text" => "New Hero Image"})

    assert Content.image_url_for(:hero) == "https://cdn.example.test/landing/hero/hero.png"
    assert Content.landing_image_map().hero.alt == "New Hero Image"
  end

  test "updating alt text without re-uploading an image updates the alt text", %{conn: conn} do
    landing_image_fixture(:hero, "https://cdn.example.test/hero.png")

    {:ok, view, _html} = live(conn, ~p"/admin/landing-images")

    view
    |> element("#edit-slot-hero-btn")
    |> render_click()

    view
    |> element("#landing-image-hero")
    |> render_submit(%{"slot" => "hero", "alt_text" => "Updated Alt Text"})

    assert Content.landing_image_map().hero.alt == "Updated Alt Text"
    assert Content.image_url_for(:hero) == "https://cdn.example.test/hero.png"
  end

  test "resetting an overridden slot clears it back to the default in the live preview", %{
    conn: conn
  } do
    landing_image_fixture(:hero, "https://cdn.example.test/hero.png")

    {:ok, view, html} = live(conn, ~p"/admin/landing-images")
    assert html =~ "https://cdn.example.test/hero.png"

    view
    |> element("#edit-slot-hero-btn")
    |> render_click()

    html =
      view
      |> element("button[phx-click='reset'][phx-value-slot='hero']")
      |> render_click()

    refute html =~ "https://cdn.example.test/hero.png"
    assert html =~ LandingImage.default_path(:hero)
    assert Content.image_url_for(:hero) == LandingImage.default_path(:hero)
  end

  test "an upload with no public URL configured flashes an error instead of silently dropping it",
       %{conn: conn} do
    previous_provider = Application.get_env(:wasomi, :storage_provider)
    on_exit(fn -> Application.put_env(:wasomi, :storage_provider, previous_provider) end)
    Application.put_env(:wasomi, :storage_provider, __MODULE__.NoPublicUrlStorageMock)

    {:ok, view, _html} = live(conn, ~p"/admin/landing-images")

    view
    |> element("#edit-slot-hero-btn")
    |> render_click()

    upload =
      file_input(view, "#landing-image-hero", :hero, [
        %{name: "hero.png", content: "fake-png-bytes", type: "image/png"}
      ])

    render_upload(upload, "hero.png")

    html =
      view
      |> element("#landing-image-hero")
      |> render_submit(%{"slot" => "hero"})

    assert html =~ "R2_PUBLIC_URL"
    refute Content.image_url_for(:hero) == "https://cdn.example.test/landing/hero/hero.png"
  end

  defmodule LandingImageStorageMock do
    def presign_upload(_user, attrs) do
      slot = Map.fetch!(attrs, "prefix")

      {:ok,
       %{
         url: "https://r2.example.test/presigned-url",
         key: "#{slot}/hero.png",
         public_url: "https://cdn.example.test/#{slot}/hero.png",
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
