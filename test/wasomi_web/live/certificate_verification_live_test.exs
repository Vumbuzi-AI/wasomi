defmodule WasomiWeb.CertificateVerificationLiveTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.CertificatesFixtures

  test "verifies a real course certificate and shows learner, course, and issue date", %{
    conn: conn
  } do
    user = user_fixture(name: "Grace Wanjiru")
    course = course_fixture(title: "GS1 Barcoding Fundamentals")

    certificate =
      certificate_fixture(
        type: :course,
        user_id: user.id,
        course_id: course.id,
        issued_at: ~U[2026-03-15 09:00:00Z]
      )

    {:ok, _lv, html} = live(conn, ~p"/certificates/253/#{certificate.gdti}")

    assert html =~ "Verified Wasomi Certificate"
    assert html =~ "Grace Wanjiru"
    assert html =~ "GS1 Barcoding Fundamentals"
    assert html =~ "March 15, 2026"
  end

  test "verifies a module certificate, showing the module's own title", %{conn: conn} do
    user = user_fixture(name: "Kevin Otieno")
    course = course_fixture(title: "GS1 Barcoding Fundamentals")
    course_module = course_module_fixture(course_id: course.id, title: "Barcode Symbology")

    certificate =
      certificate_fixture(
        type: :module,
        user_id: user.id,
        course_id: course.id,
        module_id: course_module.id
      )

    {:ok, _lv, html} = live(conn, ~p"/certificates/253/#{certificate.gdti}")

    assert html =~ "Verified Wasomi Certificate"
    assert html =~ "Barcode Symbology"
  end

  test "shows a clear not-verified state for an unrecognized GDTI, not an error page", %{
    conn: conn
  } do
    {:ok, _lv, html} = live(conn, ~p"/certificates/253/0000000000000000000000")

    assert html =~ "Certificate not found"
    assert html =~ "couldn"
    # Nothing to reference for a code that matched no certificate.
    refute html =~ "0000000000000000000000"
  end

  test "shows a certification-record footer with the GDTI when verified", %{conn: conn} do
    certificate = certificate_fixture(type: :course)

    {:ok, _lv, html} = live(conn, ~p"/certificates/253/#{certificate.gdti}")

    assert html =~ "Wasomi Certification Record"
    assert html =~ "Ref: #{certificate.gdti}"
  end

  test "never exposes the learner's email or a certificate download link", %{conn: conn} do
    user = user_fixture(name: "Amina Hassan", email: "amina.hassan@example.com")
    course = course_fixture()

    certificate =
      certificate_fixture(type: :course, user_id: user.id, course_id: course.id)

    {:ok, _lv, html} = live(conn, ~p"/certificates/253/#{certificate.gdti}")

    refute html =~ "amina.hassan@example.com"
    refute html =~ ~p"/certificates/#{certificate.id}/download"
  end

  test "no authentication is required to view the page", %{conn: conn} do
    course = course_fixture()
    certificate = certificate_fixture(type: :course, course_id: course.id)

    assert {:ok, _lv, _html} = live(conn, ~p"/certificates/253/#{certificate.gdti}")
  end

  test "shows issuer branding and view-course action, but never copy or download actions", %{
    conn: conn
  } do
    course = course_fixture(status: :published, slug: "gs1-fundamentals")
    certificate = certificate_fixture(type: :course, course_id: course.id)

    {:ok, _lv, html} = live(conn, ~p"/certificates/253/#{certificate.gdti}")

    assert html =~ "Wasomi and GS1 Kenya"
    assert html =~ "Wasomi"
    assert html =~ "GS1 Kenya"
    assert html =~ ~p"/courses/gs1-fundamentals"
    refute html =~ "Copy verification link"
    refute html =~ "copy-verification-link"
    refute html =~ "Download"
    refute html =~ ~p"/certificates/#{certificate.id}/download"
  end

  test "hides the view-course action when the course is no longer publicly viewable", %{
    conn: conn
  } do
    course = course_fixture(status: :archived)
    certificate = certificate_fixture(type: :course, course_id: course.id)

    {:ok, _lv, html} = live(conn, ~p"/certificates/253/#{certificate.gdti}")

    assert html =~ "Verified Wasomi Certificate"
    refute html =~ ~p"/courses/#{course.slug}"
    refute html =~ "Copy verification link"
    refute html =~ "copy-verification-link"
  end
end
