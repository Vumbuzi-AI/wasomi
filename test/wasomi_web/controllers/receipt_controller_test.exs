defmodule WasomiWeb.ReceiptControllerTest do
  use WasomiWeb.ConnCase, async: true

  import Mox
  import Wasomi.{AccountsFixtures, CatalogFixtures, PaymentsFixtures}

  setup :verify_on_exit!

  setup %{conn: conn} do
    user = user_fixture()
    course = course_fixture(status: :published, title: "Owned Course")

    payment =
      payment_fixture(%{
        user_id: user.id,
        course_id: course.id,
        status: :successful,
        provider_reference: "RC-DL-1"
      })

    %{conn: log_in_user(conn, user), user: user, payment: payment}
  end

  test "streams a PDF with a download disposition for the owner", %{conn: conn, payment: payment} do
    expect(Wasomi.ReceiptRendererMock, :render, fn _assigns -> {:ok, "%PDF-1.4 bytes"} end)

    conn = get(conn, ~p"/receipts/#{payment.id}/download")

    assert response_content_type(conn, :pdf)
    assert conn.status == 200
    assert conn.resp_body == "%PDF-1.4 bytes"

    assert {"content-disposition", disposition} =
             List.keyfind(conn.resp_headers, "content-disposition", 0)

    assert disposition =~ ~s(filename="wasomi-receipt-RC-DL-1.pdf")
  end

  test "404s for a payment that isn't the caller's", %{conn: conn} do
    stranger = user_fixture()
    course = course_fixture(status: :published)

    theirs =
      payment_fixture(%{
        user_id: stranger.id,
        course_id: course.id,
        status: :successful,
        provider_reference: "RC-DL-OTHER"
      })

    conn = get(conn, ~p"/receipts/#{theirs.id}/download")
    assert conn.status == 404
  end

  test "503s when the renderer fails", %{conn: conn, payment: payment} do
    expect(Wasomi.ReceiptRendererMock, :render, fn _assigns -> {:error, :boom} end)

    conn = get(conn, ~p"/receipts/#{payment.id}/download")
    assert conn.status == 503
  end

  test "redirects an anonymous request to log in", %{payment: payment} do
    conn = get(build_conn(), ~p"/receipts/#{payment.id}/download")
    assert redirected_to(conn) == ~p"/users/log_in"
  end
end
