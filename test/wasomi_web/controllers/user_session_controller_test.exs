defmodule WasomiWeb.UserSessionControllerTest do
  use WasomiWeb.ConnCase, async: false

  import Wasomi.AccountsFixtures
  alias Wasomi.Accounts
  alias Wasomi.Accounts.AuditEvent

  setup do
    %{user: user_fixture()}
  end

  describe "POST /users/log_in" do
    test "logs the user in", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("user-agent", "WasomiBrowser/1.0")
        |> post(~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboard"

      assert %AuditEvent{
               event: :login_succeeded,
               user_id: user_id,
               ip_address: "127.0.0.1",
               user_agent: "WasomiBrowser/1.0"
             } = Accounts.list_account_audit_events(user) |> List.first()

      assert user_id == user.id
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

    test "rejects unconfirmed users and redirects to confirmation instructions without creating a session",
         %{conn: conn} do
      user = user_fixture(confirmed: false)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/confirm?email=#{user.email}"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Please confirm your email address before logging in"

      assert %AuditEvent{event: :login_failed, user_id: user_id, metadata: metadata} =
               Wasomi.Repo.get_by!(AuditEvent, event: :login_failed)

      assert user_id == user.id
      assert metadata["reason"] == "unconfirmed"
      assert metadata["email_fingerprint"]
      assert metadata["email_domain"] == "example.com"
      refute inspect(metadata) =~ user.email
    end

    test "preserves a `+`-tagged email through the unconfirmed-login redirect", %{conn: conn} do
      user = user_fixture(email: "learner+tag@example.com", confirmed: false)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/users/confirm?#{[email: user.email]}"
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

    test "login following password update", %{conn: conn, user: user} do
      conn =
        conn
        |> post(~p"/users/log_in", %{
          "_action" => "password_updated",
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password updated successfully"
    end

    test "redirects to login page with invalid credentials", %{conn: conn} do
      email = "invalid@email.com"

      conn =
        conn
        |> put_req_header("user-agent", "WasomiBrowser/2.0")
        |> post(~p"/users/log_in", %{
          "user" => %{"email" => email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log_in"

      assert %AuditEvent{
               event: :login_failed,
               user_id: nil,
               metadata: metadata,
               ip_address: "127.0.0.1",
               user_agent: "WasomiBrowser/2.0"
             } = Wasomi.Repo.get_by!(AuditEvent, event: :login_failed)

      assert metadata["reason"] == "invalid_credentials"
      assert metadata["email_fingerprint"]
      assert metadata["email_domain"] == "email.com"
      refute inspect(metadata) =~ email
      refute inspect(metadata) =~ "invalid_password"
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

      assert %AuditEvent{
               event: :login_failed,
               user_id: nil,
               metadata: %{"reason" => "captcha_failed"}
             } =
               Wasomi.Repo.get_by!(AuditEvent, event: :login_failed)
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

      assert %AuditEvent{event: :login_failed, metadata: %{"reason" => "captcha_low_score"}} =
               Wasomi.Repo.get_by!(AuditEvent, event: :login_failed)
    end
  end

  describe "DELETE /users/log_out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)

      assert %AuditEvent{event: :logout, user_id: user_id} =
               Accounts.list_account_audit_events(user) |> List.first()

      assert user_id == user.id
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end
  end
end
