defmodule WasomiWeb.ActiveModeControllerTest do
  use WasomiWeb.ConnCase, async: true

  import Wasomi.AccountsFixtures

  alias Wasomi.Accounts

  defp admin_fixture(attrs \\ %{}) do
    {:ok, admin} = user_fixture(attrs) |> Accounts.update_user_role(:admin)
    admin
  end

  describe "POST /users/active-mode" do
    setup do
      admin = admin_fixture()
      learner = user_fixture()
      %{admin: admin, learner: learner}
    end

    test "admin can switch to learner mode and emits audit event", %{conn: conn, admin: admin} do
      conn =
        conn
        |> log_in_user(admin)
        |> post(~p"/users/active-mode", %{"mode" => "learner"})

      assert get_session(conn, :active_mode) == "learner"
      assert redirected_to(conn) == ~p"/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Switched to Learner Mode"

      audit_events = Accounts.list_account_audit_events(admin)

      assert Enum.any?(audit_events, fn event ->
               event.event == :active_mode_changed and
                 event.metadata["from_mode"] == "admin" and
                 event.metadata["to_mode"] == "learner"
             end)
    end

    test "admin can switch back to admin mode", %{conn: conn, admin: admin} do
      conn =
        conn
        |> log_in_user(admin)
        |> put_session(:active_mode, "learner")
        |> post(~p"/users/active-mode", %{"mode" => "admin"})

      assert get_session(conn, :active_mode) == "admin"
      assert redirected_to(conn) == ~p"/admin"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Switched to Admin Mode"
    end

    test "regular learner cannot switch to admin mode", %{conn: conn, learner: learner} do
      conn =
        conn
        |> log_in_user(learner)
        |> post(~p"/users/active-mode", %{"mode" => "admin"})

      assert get_session(conn, :active_mode) != "admin"
      assert redirected_to(conn) == ~p"/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not authorized"
    end

    test "unauthenticated visitor is redirected to login", %{conn: conn} do
      conn = post(conn, ~p"/users/active-mode", %{"mode" => "learner"})
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "invalid mode parameter is rejected", %{conn: conn, admin: admin} do
      conn =
        conn
        |> log_in_user(admin)
        |> post(~p"/users/active-mode", %{"mode" => "superadmin"})

      assert redirected_to(conn) == ~p"/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
    end
  end
end
