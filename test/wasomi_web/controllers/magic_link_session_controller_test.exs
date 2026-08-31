defmodule WasomiWeb.MagicLinkSessionControllerTest do
  use WasomiWeb.ConnCase, async: true

  import Wasomi.AccountsFixtures

  alias Wasomi.Accounts

  defp magic_token(email) do
    :ok = Accounts.deliver_magic_link(email, &"https://t.example/magic/#{&1}")
    assert_received {:email, sent}
    [_, token] = Regex.run(~r{https://t\.example/magic/([A-Za-z0-9_-]+)}, sent.text_body)
    token
  end

  describe "GET /users/log_in/:token" do
    test "renders a scanner-safe confirm page and does not consume the token", %{conn: conn} do
      user = user_fixture()
      token = magic_token(user.email)

      conn = get(conn, ~p"/users/log_in/#{token}")

      assert html_response(conn, 200) =~ "Log in to Wasomi"
      assert response(conn, 200) =~ user.email
      # still usable — a GET (scanner pre-fetch) must not burn it
      assert Accounts.get_user_by_magic_token(token)
    end

    test "redirects a bad token to the request page", %{conn: conn} do
      conn = get(conn, ~p"/users/log_in/nope")

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end
  end

  describe "POST /users/log_in/:token" do
    test "signs the user in, honours remember-me, and consumes the token", %{conn: conn} do
      user = user_fixture()
      token = magic_token(user.email)

      conn = post(conn, ~p"/users/log_in/#{token}", %{"remember_me" => "true"})

      assert get_session(conn, :user_token)
      assert conn.resp_cookies["_wasomi_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/dashboard"

      # one-time
      conn2 = post(build_conn(), ~p"/users/log_in/#{token}")
      assert redirected_to(conn2) == ~p"/users/log_in"
      refute get_session(conn2, :user_token)
    end

    test "confirms an unconfirmed account instead of bouncing it", %{conn: conn} do
      user = user_fixture(confirmed: false)
      token = magic_token(user.email)

      conn = post(conn, ~p"/users/log_in/#{token}")

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboard"
      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "sends an admin to the admin area", %{conn: conn} do
      {:ok, admin} = user_fixture() |> Accounts.update_user_role(:admin)
      token = magic_token(admin.email)

      conn = post(conn, ~p"/users/log_in/#{token}")

      assert redirected_to(conn) == ~p"/admin"
    end

    test "rejects an expired token", %{conn: conn} do
      user = user_fixture()
      token = magic_token(user.email)

      import Ecto.Query
      alias Wasomi.Accounts.UserToken
      alias Wasomi.Repo

      past = DateTime.utc_now() |> DateTime.add(-16 * 60, :second) |> DateTime.truncate(:second)

      from(t in UserToken, where: t.user_id == ^user.id and t.context == "login")
      |> Repo.update_all(set: [inserted_at: past])

      conn = post(conn, ~p"/users/log_in/#{token}")

      assert redirected_to(conn) == ~p"/users/log_in"
      refute get_session(conn, :user_token)
    end
  end
end
