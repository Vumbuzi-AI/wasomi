defmodule WasomiWeb.UserSessionControllerTest do
  use WasomiWeb.ConnCase, async: false

  import Wasomi.AccountsFixtures
  alias Wasomi.Accounts

  setup do
    %{user: user_fixture()}
  end

  describe "POST /users/log_in" do
    test "logs the user in", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_wasomi_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "logs administrators into the admin area", %{conn: conn, user: user} do
      {:ok, admin} = Accounts.update_user_role(user, :admin)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => admin.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/admin"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "login succeeds when coming from registered action without requiring direct login captcha",
         %{
           conn: conn,
           user: user
         } do
      conn =
        post(conn, ~p"/users/log_in?_action=registered", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Account created successfully!"
    end

    test "emits error message with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log_in"
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

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()},
          "captcha_token" => "invalid-token"
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Security verification failed"
      assert redirected_to(conn) == ~p"/users/log_in"
      refute get_session(conn, :user_token)
    end

    test "redirects to the v2 fallback instead of a dead end when v3's score is too low", %{
      conn: conn,
      user: user
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
        Req.Test.json(conn, %{"success" => true, "score" => 0.1, "action" => "login"})
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()},
          "captcha_token" => "low-score-token"
        })

      # No flash here by design — the redirected-to login page derives the
      # same inline message itself from show_recaptcha_v2, so a toast would
      # just duplicate it (see UserSessionController).
      refute Phoenix.Flash.get(conn.assigns.flash, :error)

      assert redirected_to(conn) == ~p"/users/log_in?show_recaptcha_v2=true"
      refute get_session(conn, :user_token)
    end
  end

  describe "DELETE /users/log_out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end
  end
end
