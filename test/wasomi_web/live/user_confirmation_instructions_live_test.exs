defmodule WasomiWeb.UserConfirmationInstructionsLiveTest do
  use WasomiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures

  alias Wasomi.Accounts
  alias Wasomi.Repo

  setup do
    %{user: user_fixture()}
  end

  describe "Resend confirmation" do
    test "renders the resend confirmation page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/confirm")
      assert html =~ "Resend confirmation instructions"
    end

    test "sends a new confirmation token", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      {:ok, conn} =
        lv
        |> form("#resend_confirmation_form", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "confirm"
    end

    test "does not send confirmation token if user is confirmed", %{conn: conn, user: user} do
      Repo.update!(Accounts.User.confirm_changeset(user))

      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      {:ok, conn} =
        lv
        |> form("#resend_confirmation_form", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      refute Repo.get_by(Accounts.UserToken, user_id: user.id)
    end

    test "does not send confirmation token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      {:ok, conn} =
        lv
        |> form("#resend_confirmation_form", user: %{email: "unknown@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

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

      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      result =
        lv
        |> form("#resend_confirmation_form", user: %{"email" => user.email})
        |> render_submit(%{"captcha_token" => "invalid-token"})

      assert result =~ "Security verification failed"
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
            "action" => "resend_confirmation"
          })
        else
          Req.Test.json(conn, %{"success" => false})
        end
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      # First attempt: invalid token -> fails
      result =
        lv
        |> form("#resend_confirmation_form", user: %{"email" => user.email})
        |> render_submit(%{"captcha_token" => "bad-token"})

      assert result =~ "Security verification failed"
      assert Repo.all(Accounts.UserToken) == []

      # Second attempt: valid token -> succeeds and redirects
      {:ok, conn} =
        lv
        |> form("#resend_confirmation_form", user: %{"email" => user.email})
        |> render_submit(%{"captcha_token" => "good-token"})
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "confirm"
    end
  end
end
