defmodule WasomiWeb.UserRegistrationLiveTest do
  use WasomiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Swoosh.TestAssertions

  alias Wasomi.Accounts.UserToken
  alias Wasomi.Repo

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

    test "prefills first name, last name and email from query params", %{conn: conn} do
      {:ok, _lv, html} =
        live(conn, ~p"/users/register?name=Jane%20Doe&email=jane@example.com")

      assert html =~ ~s(value="Jane")
      assert html =~ ~s(value="Doe")
      assert html =~ "jane@example.com"
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
    test "creates account and redirects anonymously to confirmation instructions with name and email params",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      name = "Test Learner"
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email, name: name))

      {:ok, _confirm_lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/confirm?#{[email: email, name: name]}")

      assert html =~ "Check your email"
      assert html =~ email
    end

    test "renders errors for already confirmed duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com", confirmed: true})

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email, "password" => "valid_password"}
        )
        |> render_submit()

      assert result =~ "has already been taken"
      assert result =~ "Log in"
      assert result =~ "resend the confirmation email"
    end

    test "renders the same duplicate-email error for an unconfirmed account, without emailing or enumerating it",
         %{conn: conn} do
      user =
        user_fixture(%{
          email: "unconfirmed@example.com",
          name: "Unconfirmed User",
          confirmed: false
        })

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> form("#registration_form",
          user: valid_user_attributes(email: user.email, name: user.name)
        )
        |> render_submit()

      # same outward behavior as a confirmed duplicate — no enumeration signal
      assert result =~ "has already been taken"
      assert result =~ "Log in"
      assert result =~ "resend the confirmation email"
      refute_email_sent()
      refute Repo.get_by(UserToken, user_id: user.id, context: "confirm")

      # repeating it doesn't open a side channel either
      result =
        lv
        |> form("#registration_form",
          user: valid_user_attributes(email: user.email, name: user.name)
        )
        |> render_submit()

      assert result =~ "has already been taken"
      refute_email_sent()
      refute Repo.get_by(UserToken, user_id: user.id, context: "confirm")
    end

    test "back-to-signup round trip: resubmitting the prefilled form unchanged surfaces the recovery hint",
         %{conn: conn} do
      email = unique_user_email()
      name = "Round Tripper"

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, confirm_lv, _html} =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email, name: name))
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/confirm?#{[email: email, name: name]}")

      {:ok, register_lv, register_html} =
        confirm_lv
        |> element(~s|a:fl-contains("Back to sign up")|)
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register?#{[name: name, email: email]}")

      assert register_html =~ email

      result =
        register_lv
        |> form("#registration_form", user: valid_user_attributes(email: email, name: name))
        |> render_submit()

      assert result =~ "has already been taken"
      assert result =~ "Log in"
      assert result =~ "resend the confirmation email"
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

      # Second attempt: valid token -> succeeds and moves on to confirmation
      {:ok, _confirm_lv, html} =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email))
        |> render_submit(%{"captcha_token" => "good-token"})
        |> follow_redirect(conn, ~p"/users/confirm?#{[email: email, name: "Test User"]}")

      assert html =~ "Check your email"
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

      {:ok, _confirm_lv, html} =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email))
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/confirm?#{[email: email, name: "Test User"]}")

      assert html =~ "Check your email"
    end
  end

  describe "phone number (optional)" do
    test "renders the international phone widget and a hidden E.164 field", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Phone number"
      assert html =~ "optional"
      assert has_element?(lv, "#registration-phone[phx-hook='PhoneInput'][phx-update='ignore']")
      assert has_element?(lv, "#registration-phone input[type='tel']")
      assert has_element?(lv, "input[type='hidden'][name='user[phone]']")
    end

    test "stores a submitted E.164 phone number on the new account", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      # the PhoneInput JS hook mirrors iti.getNumber() into the hidden field;
      # simulate that with an extra submit param.
      form(lv, "#registration_form", user: valid_user_attributes(email: email))
      |> render_submit(%{user: %{phone: "+254712345678"}})

      assert Wasomi.Accounts.get_user_by_email(email).phone == "+254712345678"
    end

    test "registers fine when the phone number is left blank", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      form(lv, "#registration_form", user: valid_user_attributes(email: email))
      |> render_submit()

      assert Wasomi.Accounts.get_user_by_email(email).phone == nil
    end

    test "rejects a badly formatted phone number and creates no account", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      html =
        form(lv, "#registration_form", user: valid_user_attributes(email: email))
        |> render_submit(%{user: %{phone: "0712345678"}})

      assert html =~ "valid phone number"
      assert Wasomi.Accounts.get_user_by_email(email) == nil
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
