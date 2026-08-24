defmodule WasomiWeb.AdminLive.CourseCertificateTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mox
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures

  alias Wasomi.Catalog

  setup :verify_on_exit!

  defp admin_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  test "renders existing certificate configuration", %{conn: conn} do
    course = course_fixture()

    {:ok, course} =
      Catalog.update_course_certificate(course, %{
        "certificate_enabled" => "true",
        "certificate_signatory_name" => "Jane Doe",
        "certificate_signatory_title" => "Country Manager"
      })

    {:ok, _view, html} = live(conn, ~p"/admin/courses/#{course.slug}/certificate")

    assert html =~ "Jane Doe"
    assert html =~ "Country Manager"
  end

  test "the live preview updates as signatory fields change", %{conn: conn} do
    course = course_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/certificate")

    html =
      view
      |> form("#certificate-form", %{
        "course" => %{"certificate_signatory_name" => "Jane Doe"}
      })
      |> render_change()

    assert html =~ "Jane Doe"
  end

  test "toggling issuance on requires signatory fields", %{conn: conn} do
    course = course_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/certificate")

    html =
      view
      |> form("#certificate-form", %{"course" => %{"certificate_enabled" => "true"}})
      |> render_change()

    assert html =~ "be blank"
  end

  test "saves a full certificate configuration", %{conn: conn} do
    course = course_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/certificate")

    view
    |> form("#certificate-form", %{
      "course" => %{
        "certificate_enabled" => "true",
        "certificate_signatory_name" => "Jane Doe",
        "certificate_signatory_title" => "Country Manager"
      }
    })
    |> render_submit()

    updated = Catalog.get_course!(course.id)
    assert updated.certificate_enabled
    assert updated.certificate_signatory_name == "Jane Doe"
    assert updated.certificate_signatory_title == "Country Manager"
  end

  test "uploading a signature shows a preview and persists on save", %{conn: conn} do
    previous_provider = Application.get_env(:wasomi, :storage_provider)
    previous_public_url = Application.get_env(:wasomi, :r2_public_url)

    on_exit(fn ->
      Application.put_env(:wasomi, :storage_provider, previous_provider)
      Application.put_env(:wasomi, :r2_public_url, previous_public_url)
    end)

    Application.put_env(:wasomi, :storage_provider, __MODULE__.SignatureStorageMock)
    # Matches the mock's public_url below — a locally configured
    # R2_PUBLIC_URL (via .env) would otherwise make the signature host-trust
    # check depend on the developer's machine instead of being deterministic.
    Application.put_env(:wasomi, :r2_public_url, "https://cdn.example.test")

    course = course_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/certificate")

    signature =
      file_input(view, "#certificate-form", :signature, [
        %{name: "signature.png", content: "fake-png-bytes", type: "image/png"}
      ])

    html = render_upload(signature, "signature.png")
    assert html =~ "https://cdn.example.test/certificates/signature.png"

    view
    |> form("#certificate-form", %{
      "course" => %{
        "certificate_enabled" => "true",
        "certificate_signatory_name" => "Jane Doe",
        "certificate_signatory_title" => "Country Manager"
      }
    })
    |> render_submit()

    updated = Catalog.get_course!(course.id)

    assert updated.certificate_signature_key ==
             "https://cdn.example.test/certificates/signature.png"
  end

  test "removing a saved signature clears it, but only once the form is saved", %{conn: conn} do
    previous_public_url = Application.get_env(:wasomi, :r2_public_url)
    on_exit(fn -> Application.put_env(:wasomi, :r2_public_url, previous_public_url) end)
    Application.put_env(:wasomi, :r2_public_url, "https://cdn.example.test")

    course =
      course_fixture(
        certificate_enabled: true,
        certificate_signatory_name: "Jane Doe",
        certificate_signatory_title: "Country Manager",
        certificate_signature_key: "https://cdn.example.test/certificates/old.png"
      )

    {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.slug}/certificate")
    assert html =~ "https://cdn.example.test/certificates/old.png"

    html =
      view
      |> element("button[phx-click='remove-signature'][phx-value-field='signature']")
      |> render_click()

    refute html =~ "https://cdn.example.test/certificates/old.png"
    # Not persisted until Save is clicked, same as every other field here.
    assert Catalog.get_course!(course.id).certificate_signature_key ==
             "https://cdn.example.test/certificates/old.png"

    view
    |> form("#certificate-form", %{
      "course" => %{
        "certificate_enabled" => "true",
        "certificate_signatory_name" => "Jane Doe",
        "certificate_signatory_title" => "Country Manager"
      }
    })
    |> render_submit()

    assert Catalog.get_course!(course.id).certificate_signature_key == nil
  end

  test "an upload with no public URL configured flashes an error instead of silently dropping it",
       %{conn: conn} do
    previous_provider = Application.get_env(:wasomi, :storage_provider)
    on_exit(fn -> Application.put_env(:wasomi, :storage_provider, previous_provider) end)
    Application.put_env(:wasomi, :storage_provider, __MODULE__.NoPublicUrlStorageMock)

    course = course_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/certificate")

    signature =
      file_input(view, "#certificate-form", :signature, [
        %{name: "signature.png", content: "fake-png-bytes", type: "image/png"}
      ])

    render_upload(signature, "signature.png")

    html =
      view
      |> form("#certificate-form", %{"course" => %{"certificate_enabled" => "false"}})
      |> render_submit()

    assert html =~ "R2_PUBLIC_URL"
    refute Catalog.get_course!(course.id).certificate_signature_key
  end

  test "Test PDF renders a sample certificate and pushes it to the browser for download", %{
    conn: conn
  } do
    course = course_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/certificate")

    expect(Wasomi.CertificateRendererMock, :render, fn assigns ->
      assert assigns.learner_name == "Jane Sample"
      assert assigns.serial_number == "SAMPLE-0000"
      {:ok, "%PDF-test"}
    end)

    render_click(view, "test_pdf", %{})

    assert_push_event(view, "download-pdf", %{
      data: data,
      filename: "sample-certificate.pdf"
    })

    assert Base.decode64!(data) == "%PDF-test"
  end

  defmodule SignatureStorageMock do
    def presign_upload(_user, _attrs) do
      {:ok,
       %{
         url: "https://r2.example.test/presigned-url",
         key: "certificates/signature.png",
         public_url: "https://cdn.example.test/certificates/signature.png",
         content_type: "image/png"
       }}
    end
  end

  defmodule NoPublicUrlStorageMock do
    def presign_upload(_user, _attrs) do
      {:ok,
       %{
         url: "https://r2.example.test/presigned-url",
         key: "certificates/signature.png",
         public_url: nil,
         content_type: "image/png"
       }}
    end
  end
end
