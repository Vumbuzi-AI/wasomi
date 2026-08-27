defmodule WasomiWeb.UserRegistrationLiveTest do
  use WasomiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures

  describe "Registration page" do
    test "shows a clear error when the client gives up waiting on reCAPTCHA", %{conn: conn} do
      initial_site_key = Application.get_env(:wasomi, :recaptcha_site_key)
      on_exit(fn -> Application.put_env(:wasomi, :recaptcha_site_key, initial_site_key) end)
      Application.put_env(:wasomi, :recaptcha_site_key, "test-site-key")

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      html =
        lv
        |> element("#registration_form")
        |> render_hook("recaptcha_blocked", %{})

      assert html =~ "load our security check"
    end

    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Register"
      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/dashboard")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces", "password" => "short"})

      assert result =~ "Create your account"
      assert result =~ "must have the @ sign and no spaces"
      assert result =~ "should be at least 6 character"
    end
  end

  describe "register user" do
    test "creates account and logs the user in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/dashboard"

      conn = get(conn, ~p"/dashboard")
      response = html_response(conn, 200)
      assert response =~ "Account created successfully!"
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email, "password" => "valid_password"}
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end

    test "renders error when security verification fails and prevents account creation", %{
      conn: conn
    } do
      initial_mock = Application.get_env(:wasomi, :recaptcha_mock)
      initial_site_key = Application.get_env(:wasomi, :recaptcha_site_key)
      initial_secret_key = Application.get_env(:wasomi, :recaptcha_secret_key)
      initial_req_opts = Application.get_env(:wasomi, :recaptcha_req_options)

      on_exit(fn ->
        Application.put_env(:wasomi, :recaptcha_mock, initial_mock)
        Application.put_env(:wasomi, :recaptcha_site_key, initial_site_key)
        Application.put_env(:wasomi, :recaptcha_secret_key, initial_secret_key)
        Application.put_env(:wasomi, :recaptcha_req_options, initial_req_opts)
      end)

      Application.put_env(:wasomi, :recaptcha_mock, false)
      Application.put_env(:wasomi, :recaptcha_secret_key, "secret")
      Application.put_env(:wasomi, :recaptcha_site_key, "site")

      Req.Test.stub(Wasomi.Security.Captcha, fn conn ->
        Req.Test.json(conn, %{"success" => false})
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      email = unique_user_email()
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email))
        |> render_submit(%{"captcha_token" => "invalid-token"})

      assert result =~ "Security verification failed"
      refute Wasomi.Accounts.get_user_by_email(email)
    end

    test "offers the v2 fallback checkbox instead of a dead end when v3's score is too low", %{
      conn: conn
    } do
      initial_mock = Application.get_env(:wasomi, :recaptcha_mock)
      initial_site_key = Application.get_env(:wasomi, :recaptcha_site_key)
      initial_secret_key = Application.get_env(:wasomi, :recaptcha_secret_key)
      initial_v2_site_key = Application.get_env(:wasomi, :recaptcha_v2_site_key)
      initial_req_opts = Application.get_env(:wasomi, :recaptcha_req_options)

      on_exit(fn ->
        Application.put_env(:wasomi, :recaptcha_mock, initial_mock)
        Application.put_env(:wasomi, :recaptcha_site_key, initial_site_key)
        Application.put_env(:wasomi, :recaptcha_secret_key, initial_secret_key)
        Application.put_env(:wasomi, :recaptcha_v2_site_key, initial_v2_site_key)
        Application.put_env(:wasomi, :recaptcha_req_options, initial_req_opts)
      end)

      Application.put_env(:wasomi, :recaptcha_mock, false)
      Application.put_env(:wasomi, :recaptcha_secret_key, "secret")
      Application.put_env(:wasomi, :recaptcha_site_key, "site")
      Application.put_env(:wasomi, :recaptcha_v2_site_key, "v2-site")

      Req.Test.stub(Wasomi.Security.Captcha, fn conn ->
        Req.Test.json(conn, %{"success" => true, "score" => 0.1, "action" => "register"})
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      email = unique_user_email()
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email))
        |> render_submit(%{"captcha_token" => "low-score-token"})

      assert result =~ "please also complete the checkbox below"
      assert has_element?(lv, "[data-role='recaptcha-v2-widget']")
      refute Wasomi.Accounts.get_user_by_email(email)
    end

    test "allows user to retry successfully after a failed verification attempt", %{conn: conn} do
      initial_mock = Application.get_env(:wasomi, :recaptcha_mock)
      initial_site_key = Application.get_env(:wasomi, :recaptcha_site_key)
      initial_secret_key = Application.get_env(:wasomi, :recaptcha_secret_key)
      initial_req_opts = Application.get_env(:wasomi, :recaptcha_req_options)

      on_exit(fn ->
        Application.put_env(:wasomi, :recaptcha_mock, initial_mock)
        Application.put_env(:wasomi, :recaptcha_site_key, initial_site_key)
        Application.put_env(:wasomi, :recaptcha_secret_key, initial_secret_key)
        Application.put_env(:wasomi, :recaptcha_req_options, initial_req_opts)
      end)

      Application.put_env(:wasomi, :recaptcha_mock, false)
      Application.put_env(:wasomi, :recaptcha_secret_key, "secret")
      Application.put_env(:wasomi, :recaptcha_site_key, "site")

      test_pid = self()

      Req.Test.stub(Wasomi.Security.Captcha, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        if params["response"] == "good-token" do
          Req.Test.json(conn, %{
            "success" => true,
            "score" => 0.9,
            "action" => "register"
          })
        else
          Req.Test.json(conn, %{"success" => false})
        end
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      email = unique_user_email()
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      # First attempt: invalid token -> fails
      result =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email))
        |> render_submit(%{"captcha_token" => "bad-token"})

      assert result =~ "Security verification failed"

      # Second attempt: valid token -> succeeds and triggers submit
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))
      result = render_submit(form, %{"captcha_token" => "good-token"})
      refute result =~ "Security verification failed"

      conn = follow_trigger_action(form, conn)
      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "works seamlessly when recaptcha is completely unconfigured", %{conn: conn} do
      initial_mock = Application.get_env(:wasomi, :recaptcha_mock)
      initial_site_key = Application.get_env(:wasomi, :recaptcha_site_key)
      initial_secret_key = Application.get_env(:wasomi, :recaptcha_secret_key)

      on_exit(fn ->
        Application.put_env(:wasomi, :recaptcha_mock, initial_mock)
        Application.put_env(:wasomi, :recaptcha_site_key, initial_site_key)
        Application.put_env(:wasomi, :recaptcha_secret_key, initial_secret_key)
      end)

      Application.put_env(:wasomi, :recaptcha_mock, false)
      Application.put_env(:wasomi, :recaptcha_site_key, nil)
      Application.put_env(:wasomi, :recaptcha_secret_key, nil)

      email = unique_user_email()
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/dashboard"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element(~s|main p a:fl-contains("Log in")|)
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log_in")

      assert login_html =~ "Log in"
    end
  end
end
