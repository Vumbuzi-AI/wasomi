defmodule WasomiWeb.AdminInvitationAcceptLiveTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures

  alias Wasomi.Accounts

  defp invite(email) do
    {:ok, inviter} = user_fixture() |> Accounts.update_user_role(:admin)
    {:ok, {_invitation, token}} = Accounts.invite_admin(email, inviter)
    token
  end

  test "shows a not-found state for an unknown token", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/admin-invitations/accept/nope")
    assert html =~ "Invitation not found"
  end

  describe "email has no account yet" do
    test "creates a confirmed admin account and sends them to sign in", %{conn: conn} do
      token = invite("new.admin@example.com")

      {:ok, lv, _html} = live(conn, ~p"/admin-invitations/accept/#{token}")

      assert {:error, {:redirect, %{to: "/users/log_in"}}} =
               lv
               |> form("#accept_admin_form",
                 user: %{
                   name: "New Admin",
                   password: "supersecret",
                   password_confirmation: "supersecret"
                 }
               )
               |> render_submit()

      user = Accounts.get_user_by_email("new.admin@example.com")
      assert user.role == :admin
      assert user.confirmed_at
    end

    test "surfaces validation errors and creates nothing", %{conn: conn} do
      token = invite("weak@example.com")

      {:ok, lv, _html} = live(conn, ~p"/admin-invitations/accept/#{token}")

      html =
        lv
        |> form("#accept_admin_form",
          user: %{name: "Weak", password: "short", password_confirmation: "short"}
        )
        |> render_submit()

      assert html =~ "should be at least 6 character"
      refute Accounts.get_user_by_email("weak@example.com")
    end
  end

  describe "email already has an account" do
    test "one-click accept when signed in as the invited email", %{conn: conn} do
      learner = user_fixture(%{email: "promote.me@example.com"})
      token = invite("promote.me@example.com")

      {:ok, lv, _html} =
        conn |> log_in_user(learner) |> live(~p"/admin-invitations/accept/#{token}")

      assert {:error, {:live_redirect, %{to: "/admin"}}} =
               lv |> element("button", "Accept and open the admin area") |> render_click()

      assert Accounts.get_user!(learner.id).role == :admin
    end

    test "asks a signed-out visitor to sign in as that email", %{conn: conn} do
      _learner = user_fixture(%{email: "known@example.com"})
      token = invite("known@example.com")

      {:ok, _lv, html} = live(conn, ~p"/admin-invitations/accept/#{token}")

      assert html =~ "Sign in with"
      assert html =~ "known@example.com"
      refute html =~ "accept_admin_form"
    end

    test "asks a visitor signed in as someone else to sign in as that email", %{conn: conn} do
      _learner = user_fixture(%{email: "known@example.com"})
      other = user_fixture(%{email: "other@example.com"})
      token = invite("known@example.com")

      {:ok, lv, html} =
        conn |> log_in_user(other) |> live(~p"/admin-invitations/accept/#{token}")

      assert html =~ "Sign in with"
      refute html =~ "Accept and open the admin area"

      # even a forced "accept" event must not promote the invited account
      render_hook(lv, "accept", %{})
      assert Wasomi.Accounts.get_user_by_email("known@example.com").role == :learner
    end
  end
end
