defmodule WasomiWeb.CertificateControllerTest do
  use WasomiWeb.ConnCase

  import Wasomi.CertificatesFixtures
  import Mox

  setup :register_and_log_in_user
  setup :verify_on_exit!

  test "redirects an owner to a short-lived signed download", %{conn: conn, user: user} do
    certificate = certificate_fixture(user_id: user.id)

    expect(Wasomi.CertificateStorageMock, :signed_url, fn key, opts ->
      assert key == certificate.file_key
      assert opts[:expires_in] == 300
      {:ok, "https://r2.example.test/private-certificate"}
    end)

    conn = get(conn, ~p"/certificates/#{certificate.id}/download")
    assert redirected_to(conn) == "https://r2.example.test/private-certificate"
  end

  test "does not expose another learner's certificate", %{conn: conn} do
    certificate = certificate_fixture()

    assert_error_sent :not_found, fn ->
      get(conn, ~p"/certificates/#{certificate.id}/download")
    end
  end
end
