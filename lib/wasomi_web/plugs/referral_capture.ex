defmodule WasomiWeb.Plugs.ReferralCapture do
  @moduledoc """
  Persists a `?ref=CODE` referral code so a later sign-up can attribute it.

  Any browser request carrying `?ref=` gets a 30-day signed cookie; the code
  is also mirrored into the session so `UserRegistrationLive` can read it.
  Attribution itself (one referrer per referee, self-referral blocked) is
  enforced in `Wasomi.Referrals.attribute/2`.
  """

  import Plug.Conn

  @cookie "_wasomi_referral"
  @max_age 60 * 60 * 24 * 30
  @cookie_opts [sign: true, max_age: @max_age, same_site: "Lax", http_only: true]

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> store_from_param()
    |> mirror_to_session()
  end

  defp store_from_param(conn) do
    conn = fetch_query_params(conn)

    case conn.query_params["ref"] do
      code when is_binary(code) and code != "" ->
        put_resp_cookie(conn, @cookie, String.slice(code, 0, 64), @cookie_opts)

      _ ->
        conn
    end
  end

  # Mirror the code into the session so `UserRegistrationLive` can read it.
  defp mirror_to_session(conn) do
    if get_session(conn, :referral_ref) do
      conn
    else
      conn = fetch_cookies(conn, signed: [@cookie])

      case conn.cookies[@cookie] do
        code when is_binary(code) and code != "" -> put_session(conn, :referral_ref, code)
        _ -> conn
      end
    end
  end
end
