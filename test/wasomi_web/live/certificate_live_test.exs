defmodule WasomiWeb.CertificateLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.CertificatesFixtures

  @create_attrs %{
    type: :module,
    serial_number: "some serial_number",
    file_key: "some file_key",
    issued_at: "2026-06-24T10:02:00Z"
  }
  @update_attrs %{
    type: :course,
    serial_number: "some updated serial_number",
    file_key: "some updated file_key",
    issued_at: "2026-06-25T10:02:00Z"
  }
  @invalid_attrs %{type: nil, serial_number: nil, file_key: nil, issued_at: nil}

  defp create_certificate(_) do
    certificate = certificate_fixture()
    %{certificate: certificate}
  end

  describe "Index" do
    setup [:create_certificate]

    test "lists all certificates", %{conn: conn, certificate: certificate} do
      {:ok, _index_live, html} = live(conn, ~p"/certificates")

      assert html =~ "Listing Certificates"
      assert html =~ certificate.serial_number
    end

    test "saves new certificate", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/certificates")

      assert index_live |> element("a", "New Certificate") |> render_click() =~
               "New Certificate"

      assert_patch(index_live, ~p"/certificates/new")

      assert index_live
             |> form("#certificate-form", certificate: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#certificate-form", certificate: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/certificates")

      html = render(index_live)
      assert html =~ "Certificate created successfully"
      assert html =~ "some serial_number"
    end

    test "updates certificate in listing", %{conn: conn, certificate: certificate} do
      {:ok, index_live, _html} = live(conn, ~p"/certificates")

      assert index_live |> element("#certificates-#{certificate.id} a", "Edit") |> render_click() =~
               "Edit Certificate"

      assert_patch(index_live, ~p"/certificates/#{certificate}/edit")

      assert index_live
             |> form("#certificate-form", certificate: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#certificate-form", certificate: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/certificates")

      html = render(index_live)
      assert html =~ "Certificate updated successfully"
      assert html =~ "some updated serial_number"
    end

    test "deletes certificate in listing", %{conn: conn, certificate: certificate} do
      {:ok, index_live, _html} = live(conn, ~p"/certificates")

      assert index_live
             |> element("#certificates-#{certificate.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#certificates-#{certificate.id}")
    end
  end

  describe "Show" do
    setup [:create_certificate]

    test "displays certificate", %{conn: conn, certificate: certificate} do
      {:ok, _show_live, html} = live(conn, ~p"/certificates/#{certificate}")

      assert html =~ "Show Certificate"
      assert html =~ certificate.serial_number
    end

    test "updates certificate within modal", %{conn: conn, certificate: certificate} do
      {:ok, show_live, _html} = live(conn, ~p"/certificates/#{certificate}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Certificate"

      assert_patch(show_live, ~p"/certificates/#{certificate}/show/edit")

      assert show_live
             |> form("#certificate-form", certificate: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#certificate-form", certificate: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/certificates/#{certificate}")

      html = render(show_live)
      assert html =~ "Certificate updated successfully"
      assert html =~ "some updated serial_number"
    end
  end
end
