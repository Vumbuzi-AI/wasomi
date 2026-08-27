defmodule WasomiWeb.UserConfirmationControllerTest do
  use WasomiWeb.ConnCase, async: true

  import Wasomi.AccountsFixtures

  alias Wasomi.Accounts
  alias Wasomi.Repo

  setup do
    %{user: user_fixture(confirmed: false)}
  end

  describe "GET /users/confirm/:token" do
    test "shows the confirm step without confirming the account", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      conn = get(conn, ~p"/users/confirm/#{token}")

      assert html_response(conn, 200) =~ "Confirm your account"
      assert html_response(conn, 200) =~ user.email
      refute get_session(conn, :user_token)
      refute Accounts.get_user!(user.id).confirmed_at
      # token must survive a bare GET (what a scanner would do)
      assert Repo.get_by(Accounts.UserToken, user_id: user.id, context: "confirm")
    end

    test "redirects invalid anonymous links to confirmation instructions", %{
      conn: conn,
      user: user
    } do
      conn = get(conn, ~p"/users/confirm/invalid-token")

      assert redirected_to(conn) == ~p"/users/confirm"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or it has expired"
      refute get_session(conn, :user_token)
      refute Accounts.get_user!(user.id).confirmed_at
    end

    test "redirects already-confirmed signed-in users without an invalid-link warning", %{
      conn: conn
    } do
      confirmed_user = user_fixture()

      conn =
        conn
        |> log_in_user(confirmed_user)
        |> get(~p"/users/confirm/invalid-token")

      assert redirected_to(conn) == ~p"/dashboard"
      refute Phoenix.Flash.get(conn.assigns.flash, :error)
    end
  end

  describe "POST /users/confirm/:token" do
    test "confirms the user, logs them in, and redirects to the learner dashboard", %{
      conn: conn,
      user: user
    } do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      conn = post(conn, ~p"/users/confirm/#{token}")

      assert redirected_to(conn) == ~p"/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Email confirmed"
      assert get_session(conn, :user_token)
      assert Accounts.get_user!(user.id).confirmed_at
      refute Repo.get_by(Accounts.UserToken, user_id: user.id, context: "confirm")
    end

    test "confirms an administrator and redirects to the admin dashboard", %{
      conn: conn,
      user: user
    } do
      {:ok, admin} = Accounts.update_user_role(user, :admin)

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(admin, url)
        end)

      conn = post(conn, ~p"/users/confirm/#{token}")

      assert redirected_to(conn) == ~p"/admin"
      assert get_session(conn, :user_token)
      assert Accounts.get_user!(admin.id).confirmed_at
    end

    test "redirects invalid anonymous links to confirmation instructions", %{
      conn: conn,
      user: user
    } do
      conn = post(conn, ~p"/users/confirm/invalid-token")

      assert redirected_to(conn) == ~p"/users/confirm"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or it has expired"
      refute get_session(conn, :user_token)
      refute Accounts.get_user!(user.id).confirmed_at
    end

    test "a token already consumed by an earlier visit can't be used again", %{
      conn: conn,
      user: user
    } do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      assert {:ok, _} = Accounts.confirm_user(token)

      conn = post(conn, ~p"/users/confirm/#{token}")

      assert redirected_to(conn) == ~p"/users/confirm"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or it has expired"
    end

    test "redirects already-confirmed signed-in users without an invalid-link warning", %{
      conn: conn
    } do
      confirmed_user = user_fixture()

      conn =
        conn
        |> log_in_user(confirmed_user)
        |> post(~p"/users/confirm/invalid-token")

      assert redirected_to(conn) == ~p"/dashboard"
      refute Phoenix.Flash.get(conn.assigns.flash, :error)
    end
  end
end
