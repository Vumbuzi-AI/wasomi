defmodule WasomiWeb.UserLoginLiveTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "Log in"
      assert html =~ "Sign up"
      assert html =~ "Forgot your password?"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/log_in")
        |> follow_redirect(conn, ~p"/dashboard")

      assert {:ok, _conn} = result
    end

    test "renders the v2 fallback checkbox when redirected here with show_recaptcha_v2=true", %{
      conn: conn
    } do
      initial_v2_site_key = Application.get_env(:wasomi, :recaptcha_v2_site_key)
      on_exit(fn -> Application.put_env(:wasomi, :recaptcha_v2_site_key, initial_v2_site_key) end)
      Application.put_env(:wasomi, :recaptcha_v2_site_key, "v2-site")

      {:ok, lv, html} = live(conn, ~p"/users/log_in?show_recaptcha_v2=true")

      assert html =~ "please also complete the checkbox below"
      assert has_element?(lv, "[data-role='recaptcha-v2-widget']")
    end

    test "does not render the v2 fallback checkbox on a plain visit", %{conn: conn} do
      initial_v2_site_key = Application.get_env(:wasomi, :recaptcha_v2_site_key)
      on_exit(fn -> Application.put_env(:wasomi, :recaptcha_v2_site_key, initial_v2_site_key) end)
      Application.put_env(:wasomi, :recaptcha_v2_site_key, "v2-site")

      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      refute html =~ "please also complete the checkbox below"
    end
  end

  describe "user login" do
    test "redirects if user login with valid credentials", %{conn: conn} do
      password = "123456789abcd"
      user = user_fixture(%{password: password})

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form", user: %{email: user.email, password: password, remember_me: true})

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "redirects to login page with a flash error if there are no valid credentials", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form",
          user: %{email: "test@email.com", password: "123456", remember_me: true}
        )

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"

      assert redirected_to(conn) == "/users/log_in"
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      {:ok, _login_live, login_html} =
        lv
        |> element(~s|main a:fl-contains("Sign up")|)
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register")

      assert login_html =~ "Register"
    end

    test "redirects to forgot password page when the Forgot Password button is clicked", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      {:ok, conn} =
        lv
        |> element(~s|main a:fl-contains("Forgot your password?")|)
        |> render_click()
        |> follow_redirect(conn, ~p"/users/reset_password")

      assert conn.resp_body =~ "Forgot your password?"
    end
  end
end
