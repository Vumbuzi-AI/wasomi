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
        "certificate_issuer_name" => "GS1 Kenya",
        "certificate_signatory_name" => "Jane Doe",
        "certificate_signatory_title" => "Country Manager"
      })

    {:ok, _view, html} = live(conn, ~p"/admin/courses/#{course.id}/certificate")

    assert html =~ "GS1 Kenya"
    assert html =~ "Jane Doe"
    assert html =~ "Country Manager"
  end

  test "the live preview updates as issuer/signatory fields change", %{conn: conn} do
    course = course_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/certificate")

    html =
      view
      |> form("#certificate-form", %{
        "course" => %{"certificate_issuer_name" => "GS1 Kenya"}
      })
      |> render_change()

    assert html =~ "GS1 Kenya"
  end

  test "toggling issuance on requires issuer and signatory fields", %{conn: conn} do
    course = course_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/certificate")

    html =
      view
      |> form("#certificate-form", %{"course" => %{"certificate_enabled" => "true"}})
      |> render_change()

    assert html =~ "be blank"
  end

  test "saves a full certificate configuration", %{conn: conn} do
    course = course_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/certificate")

    view
    |> form("#certificate-form", %{
      "course" => %{
        "certificate_enabled" => "true",
        "certificate_issuer_name" => "GS1 Kenya",
        "certificate_signatory_name" => "Jane Doe",
        "certificate_signatory_title" => "Country Manager"
      }
    })
    |> render_submit()

    updated = Catalog.get_course!(course.id)
    assert updated.certificate_enabled
    assert updated.certificate_issuer_name == "GS1 Kenya"
    assert updated.certificate_signatory_name == "Jane Doe"
    assert updated.certificate_signatory_title == "Country Manager"
  end

  test "uploading a signature shows a preview and persists on save", %{conn: conn} do
    previous_provider = Application.get_env(:wasomi, :storage_provider)
    on_exit(fn -> Application.put_env(:wasomi, :storage_provider, previous_provider) end)
    Application.put_env(:wasomi, :storage_provider, __MODULE__.SignatureStorageMock)

    course = course_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/certificate")

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
        "certificate_issuer_name" => "GS1 Kenya",
        "certificate_signatory_name" => "Jane Doe",
        "certificate_signatory_title" => "Country Manager"
      }
    })
    |> render_submit()

    updated = Catalog.get_course!(course.id)

    assert updated.certificate_signature_key ==
             "https://cdn.example.test/certificates/signature.png"
  end

  test "Test PDF renders a sample certificate and pushes it to the browser for download", %{
    conn: conn
  } do
    course = course_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/certificate")

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
end
