defmodule WasomiWeb.AdminLive.SettingsTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures

  alias Wasomi.Accounts

  @valid_password "hello world!123"

  defp admin_fixture(attrs) do
    user = user_fixture(attrs)
    {:ok, admin} = Accounts.update_user_role(user, :admin)
    admin
  end

  setup %{conn: conn} do
    admin = admin_fixture(%{password: @valid_password})
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  test "renders the email and password sections", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/admin/settings")

    assert html =~ "Account settings"
    assert html =~ "Change Email"
    assert html =~ "Change Password"
  end

  test "sends a confirmation link when changing the email", %{conn: conn, admin: admin} do
    new_email = unique_user_email()

    {:ok, lv, _html} = live(conn, ~p"/admin/settings")

    html =
      lv
      |> form("#email_form", %{
        "current_password" => @valid_password,
        "user" => %{"email" => new_email}
      })
      |> render_submit()

    assert html =~ "A link to confirm your email change has been sent to the new address."
    assert Accounts.get_user_by_email(admin.email)
    refute Accounts.get_user_by_email(new_email)
  end

  test "rejects an email change with the wrong current password", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/settings")

    html =
      lv
      |> form("#email_form", %{
        "current_password" => "wrong",
        "user" => %{"email" => unique_user_email()}
      })
      |> render_submit()

    assert html =~ "is not valid"
  end

  test "updates the password and triggers a re-login", %{conn: conn, admin: admin} do
    new_password = "brand new pass!456"

    {:ok, lv, _html} = live(conn, ~p"/admin/settings")

    form =
      form(lv, "#password_form", %{
        "current_password" => @valid_password,
        "user" => %{
          "email" => admin.email,
          "password" => new_password,
          "password_confirmation" => new_password
        }
      })

    render_submit(form)

    new_conn = follow_trigger_action(form, conn)
    assert redirected_to(new_conn) == ~p"/admin/settings"
    assert get_session(new_conn, :user_token) != get_session(conn, :user_token)
    assert Accounts.get_user_by_email_and_password(admin.email, new_password)
  end

  test "confirms an email change from the token route", %{conn: conn, admin: admin} do
    new_email = unique_user_email()
    {:ok, applied} = Accounts.apply_user_email(admin, @valid_password, %{email: new_email})

    token =
      extract_user_token(fn url_fun ->
        Accounts.deliver_user_update_email_instructions(applied, admin.email, url_fun)
      end)

    {:error, {:live_redirect, %{to: "/admin/settings", flash: %{"info" => info}}}} =
      live(conn, ~p"/admin/settings/confirm_email/#{token}")

    assert info =~ "Email changed successfully"
    assert Accounts.get_user_by_email(new_email)
    refute Accounts.get_user_by_email(admin.email)
  end
end
