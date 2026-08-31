defmodule WasomiWeb.UserLoginLiveTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Wasomi.AccountsFixtures

  defp advance(lv, email) do
    lv |> form("#login_email_form", user: %{email: email}) |> render_submit()
  end

  describe "email step" do
    test "asks for an email first, not a password", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "Continue"
      assert has_element?(lv, "#login_email_form")
      refute html =~ "Enter your password"
      refute html =~ "Forgot your password?"
    end

    test "redirects if already logged in", %{conn: conn} do
      assert {:ok, _} =
               conn
               |> log_in_user(user_fixture())
               |> live(~p"/users/log_in")
               |> follow_redirect(conn, ~p"/dashboard")
    end

    test "rejects a malformed email without advancing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      html = advance(lv, "not-an-email")

      assert html =~ "Enter a valid email address."
      refute html =~ "Enter your password"
    end
  end

  describe "choose step" do
    test "shows password and magic-link options after Continue", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      html = advance(lv, "learner@example.com")

      assert html =~ "learner@example.com"
      assert html =~ "Enter your password"
      assert html =~ "Forgot your password?"
      assert has_element?(lv, "#login_form")
      assert has_element?(lv, "#magic_link_form")
      assert html =~ "Email me a login link instead"
    end

    test "Change goes back to the email step", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")
      advance(lv, "learner@example.com")

      html = lv |> element("button", "Change") |> render_click()

      assert html =~ "Continue"
      refute html =~ "Enter your password"
    end
  end

  describe "password login" do
    test "valid credentials sign the user in", %{conn: conn} do
      password = "123456789abcd"
      user = user_fixture(%{password: password})

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")
      advance(lv, user.email)

      conn =
        form(lv, "#login_form", user: %{email: user.email, password: password, remember_me: true})
        |> submit_form(conn)

      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "bad credentials redirect back with a flash", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")
      advance(lv, "nobody@example.com")

      conn =
        form(lv, "#login_form",
          user: %{email: "nobody@example.com", password: "wrongpass", remember_me: true}
        )
        |> submit_form(conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == "/users/log_in"
    end
  end

  describe "magic link" do
    test "sends a link and shows the check-your-email state", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")
      advance(lv, user.email)

      html = lv |> form("#magic_link_form") |> render_submit()

      assert html =~ "Check your email"
      assert html =~ user.email
      assert_email_sent(subject: "Your Wasomi login link")
    end

    test "shows the same state for an unknown email and sends nothing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")
      advance(lv, "ghost@example.com")

      html = lv |> form("#magic_link_form") |> render_submit()

      assert html =~ "Check your email"
      assert_no_email_sent()
    end

    test "'use a different email' returns to the email step", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")
      advance(lv, "someone@example.com")
      lv |> form("#magic_link_form") |> render_submit()

      html = lv |> element("button", "Use a different email") |> render_click()

      assert html =~ "Continue"
    end
  end

  describe "reCAPTCHA v2 fallback" do
    setup do
      initial = Application.get_env(:wasomi, :recaptcha_v2_site_key)
      Application.put_env(:wasomi, :recaptcha_v2_site_key, "v2-site")
      on_exit(fn -> Application.put_env(:wasomi, :recaptcha_v2_site_key, initial) end)
    end

    test "renders the checkbox when bounced here with show_recaptcha_v2=true", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/log_in?show_recaptcha_v2=true")

      assert html =~ "please also complete the checkbox below"
      assert has_element?(lv, "[data-role='recaptcha-v2-widget']")
    end

    test "not shown on a plain visit", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")
      refute html =~ "please also complete the checkbox below"
    end
  end

  describe "navigation" do
    test "Sign up leads to registration", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      assert {:ok, _, html} =
               lv
               |> element(~s|main a:fl-contains("Sign up")|)
               |> render_click()
               |> follow_redirect(conn, ~p"/users/register")

      assert html =~ "Register"
    end

    test "Forgot your password leads to the reset page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")
      advance(lv, "learner@example.com")

      assert {:ok, conn} =
               lv
               |> element(~s|a:fl-contains("Forgot your password?")|)
               |> render_click()
               |> follow_redirect(conn, ~p"/users/reset_password")

      assert conn.resp_body =~ "Forgot your password?"
    end
  end
end
