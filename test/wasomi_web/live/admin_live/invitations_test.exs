defmodule WasomiWeb.AdminLive.InvitationsTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Wasomi.AccountsFixtures

  alias Wasomi.Accounts

  defp admin_conn(%{conn: conn}) do
    {:ok, admin} = user_fixture() |> Accounts.update_user_role(:admin)
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  describe "authorization" do
    test "a learner cannot open the page", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/admin/invitations")
    end
  end

  describe "as an admin" do
    setup :admin_conn

    test "sends an invitation and lists it as pending", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/invitations")

      html =
        lv
        |> form("#invite_admin_form", invitation: %{email: "invitee@example.com"})
        |> render_submit()

      assert html =~ "Invitation sent to invitee@example.com"
      assert html =~ "invitee@example.com"
      assert html =~ "pending"
      assert_email_sent(subject: "You're invited to the Wasomi admin team")

      assert [%{email: "invitee@example.com", status: :pending}] =
               Accounts.list_admin_invitations()
    end

    test "rejects an email that is already an admin", %{conn: conn} do
      {:ok, other} = user_fixture() |> Accounts.update_user_role(:admin)
      {:ok, lv, _html} = live(conn, ~p"/admin/invitations")

      html =
        lv
        |> form("#invite_admin_form", invitation: %{email: other.email})
        |> render_submit()

      assert html =~ "already belongs to an admin"
      assert Accounts.list_admin_invitations() == []
    end

    test "rejects a duplicate pending invitation", %{conn: conn, admin: admin} do
      {:ok, _} = Accounts.invite_admin("dup@example.com", admin)
      {:ok, lv, _html} = live(conn, ~p"/admin/invitations")

      html =
        lv
        |> form("#invite_admin_form", invitation: %{email: "dup@example.com"})
        |> render_submit()

      assert html =~ "already a pending invitation"
    end

    test "shows a validation error for a malformed email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/invitations")

      html =
        lv
        |> form("#invite_admin_form", invitation: %{email: "not-an-email"})
        |> render_submit()

      assert html =~ "must be a valid email"
      assert_no_email_sent()
    end

    test "resends and revokes a pending invitation", %{conn: conn, admin: admin} do
      {:ok, {invitation, _}} = Accounts.invite_admin("resend@example.com", admin)
      {:ok, lv, _html} = live(conn, ~p"/admin/invitations")

      lv |> element("#invitation-#{invitation.id} button", "Resend") |> render_click()
      assert_email_sent(subject: "You're invited to the Wasomi admin team")

      html =
        lv |> element("#invitation-#{invitation.id} button", "Revoke") |> render_click()

      assert html =~ "Invitation revoked"
      assert Accounts.get_admin_invitation!(invitation.id).status == :revoked
      refute html =~ "#invitation-#{invitation.id} button"
    end
  end
end
