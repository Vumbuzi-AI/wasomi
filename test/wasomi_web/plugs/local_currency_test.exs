defmodule WasomiWeb.Plugs.LocalCurrencyTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias WasomiWeb.Plugs.LocalCurrency
  import Mox

  setup do
    verify_on_exit!()

    opts =
      Plug.Session.init(
        store: :cookie,
        key: "_wasomi_key",
        signing_salt: "some_salt"
      )

    conn =
      conn(:get, "/")
      |> Plug.Session.call(opts)
      |> fetch_session()

    {:ok, %{conn: conn}}
  end

  test "returns existing display_currency from session if present", %{conn: conn} do
    conn =
      conn
      |> put_session(:display_currency, "GBP")
      |> LocalCurrency.call(LocalCurrency.init([]))

    assert get_session(conn, :display_currency) == "GBP"
  end

  test "Cloudflare cf-ipcountry header sets currency immediately", %{conn: conn} do
    conn =
      conn
      |> put_req_header("cf-ipcountry", "FR")
      |> LocalCurrency.call(LocalCurrency.init([]))

    assert get_session(conn, :display_currency) == "EUR"
  end

  test "Cloudflare cf-ipcountry header ignores XX and T1", %{conn: conn} do
    conn =
      conn
      |> put_req_header("cf-ipcountry", "XX")
      |> LocalCurrency.call(LocalCurrency.init([]))

    assert get_session(conn, :display_currency) == "USD"
  end

  test "conn.remote_ip as nil sets the default configured currency safely", %{conn: conn} do
    conn = %{conn | remote_ip: nil}
    conn = LocalCurrency.call(conn, LocalCurrency.init([]))

    assert get_session(conn, :display_currency) == "USD"
  end

  test "private IPs bypass HTTP lookups and use the default configured currency safely", %{
    conn: conn
  } do
    conn1 = %{conn | remote_ip: {127, 0, 0, 1}} |> LocalCurrency.call(LocalCurrency.init([]))
    assert get_session(conn1, :display_currency) == "USD"

    conn2 = %{conn | remote_ip: {10, 0, 0, 1}} |> LocalCurrency.call(LocalCurrency.init([]))
    assert get_session(conn2, :display_currency) == "USD"
  end

  test "uses the configured geolocation client for a public IP", %{conn: conn} do
    expect(Wasomi.GeolocationMock, :country_code, fn "8.8.8.8" -> {:ok, "US"} end)

    conn = %{conn | remote_ip: {8, 8, 8, 8}}
    conn = LocalCurrency.call(conn, LocalCurrency.init([]))

    assert get_session(conn, :display_currency) == "USD"
  end
end
