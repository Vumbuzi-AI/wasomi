defmodule WasomiWeb.UserForgotPasswordLiveTest do
  use WasomiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures

  alias Wasomi.Accounts
  alias Wasomi.Repo

  describe "Forgot password page" do
    test "renders email page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/reset_password")

      assert html =~ "Forgot your password?"
      assert has_element?(lv, ~s|a[href="#{~p"/users/register"}"]|, "Create an account")
      assert has_element?(lv, ~s|a[href="#{~p"/users/log_in"}"]|, "Log in")
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/reset_password")
        |> follow_redirect(conn, ~p"/dashboard")

      assert {:ok, _conn} = result
    end
  end

  describe "Reset link" do
    setup do
      %{user: user_fixture()}
    end

    test "sends a new reset password token", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset_password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", user: %{"email" => user.email})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context ==
               "reset_password"
    end

    test "does not send reset password token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset_password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", user: %{"email" => "unknown@example.com"})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
      assert Repo.all(Accounts.UserToken) == []
    end

    test "renders error when security verification fails", %{conn: conn, user: user} do
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

      {:ok, lv, _html} = live(conn, ~p"/users/reset_password")

      result =
        lv
        |> form("#reset_password_form", user: %{"email" => user.email})
        |> render_submit(%{"captcha_token" => "invalid-token"})

      assert result =~ "Security verification failed"
      assert Repo.all(Accounts.UserToken) == []
    end

    test "offers the v2 fallback checkbox instead of a dead end when v3's score is too low", %{
      conn: conn,
      user: user
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
        Req.Test.json(conn, %{"success" => true, "score" => 0.1, "action" => "forgot_password"})
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      {:ok, lv, _html} = live(conn, ~p"/users/reset_password")

      result =
        lv
        |> form("#reset_password_form", user: %{"email" => user.email})
        |> render_submit(%{"captcha_token" => "low-score-token"})

      assert result =~ "please also complete the checkbox below"
      assert has_element?(lv, "[data-role='recaptcha-v2-widget']")
      assert Repo.all(Accounts.UserToken) == []
    end

    test "allows retrying successfully after a verification failure", %{conn: conn, user: user} do
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
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        if params["response"] == "good-token" do
          Req.Test.json(conn, %{
            "success" => true,
            "score" => 0.9,
            "action" => "forgot_password"
          })
        else
          Req.Test.json(conn, %{"success" => false})
        end
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      {:ok, lv, _html} = live(conn, ~p"/users/reset_password")

      # First attempt: invalid token -> fails
      result =
        lv
        |> form("#reset_password_form", user: %{"email" => user.email})
        |> render_submit(%{"captcha_token" => "bad-token"})

      assert result =~ "Security verification failed"
      assert Repo.all(Accounts.UserToken) == []

      # Second attempt: valid token -> succeeds and redirects
      {:ok, conn} =
        lv
        |> form("#reset_password_form", user: %{"email" => user.email})
        |> render_submit(%{"captcha_token" => "good-token"})
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "reset_password"
    end
  end
end
