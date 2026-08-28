defmodule WasomiWeb.UserConfirmationInstructionsLiveTest do
  use WasomiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures

  alias Wasomi.Accounts
  alias Wasomi.Repo

  setup do
    %{user: user_fixture(confirmed: false)}
  end

  describe "Resend confirmation" do
    test "renders the resend confirmation page on cold visit", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/confirm")
      assert html =~ "Resend confirmation"
      assert html =~ "Email address"
    end

    test "renders the check your email page with prefilled email and name from query params", %{
      conn: conn,
      user: user
    } do
      {:ok, _view, html} =
        live(conn, ~p"/users/confirm?email=#{user.email}&name=#{user.name}")

      assert html =~ "Check your email"
      assert html =~ user.email
      assert html =~ "Back to sign up"
      refute html =~ "Already confirmed?"
    end

    test "navigates directly to registration on Back to sign up with prefilled name and email",
         %{
           conn: conn,
           user: user
         } do
      {:ok, lv, _html} =
        live(conn, ~p"/users/confirm?email=#{user.email}&name=#{user.name}")

      {:ok, _register_lv, html} =
        lv
        |> element(~s|a:fl-contains("Back to sign up")|)
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register?name=#{user.name}&email=#{user.email}")

      assert html =~ "Create your account"
      assert html =~ user.name
      assert html =~ user.email
    end

    test "sends a new confirmation token from the anonymous resend form", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      html =
        lv
        |> form("#resend_confirmation_form", user: %{email: user.email})
        |> render_submit()

      assert html =~ "If your email is in our system"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id, context: "confirm")
    end

    test "sends a new confirmation token for the signed-in user without an email field", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      html =
        lv
        |> form("#resend_confirmation_form")
        |> render_submit()

      assert html =~ "A new confirmation link has been sent to your email"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id, context: "confirm")
    end

    test "does not send another confirmation token inside the resend cooldown", %{
      conn: conn,
      user: user
    } do
      {:ok, _email} =
        Accounts.deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))

      assert Repo.aggregate(Accounts.UserToken, :count) == 1

      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      html =
        lv
        |> form("#resend_confirmation_form", user: %{email: user.email})
        |> render_submit()

      assert html =~ "If your email is in our system"

      assert Repo.aggregate(Accounts.UserToken, :count) == 1
    end

    test "shows the rate-limited message (not a false success) on a second signed-in resend inside the cooldown",
         %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      lv |> form("#resend_confirmation_form") |> render_submit()
      assert confirm_token_count(user) == 1

      html = lv |> form("#resend_confirmation_form") |> render_submit()

      assert html =~ "You already requested a link recently"
      refute html =~ "A new confirmation link has been sent"
      assert confirm_token_count(user) == 1
    end

    test "preserves a `+`-tagged email through the query string, both display and resend", %{
      conn: conn
    } do
      user = user_fixture(email: "learner+promo@example.com", confirmed: false)

      {:ok, lv, html} = live(conn, ~p"/users/confirm?#{[email: user.email, name: user.name]}")

      assert html =~ "learner+promo@example.com"
      refute html =~ "learner promo@example.com"

      html =
        lv
        |> form("#resend_confirmation_form", user: %{email: user.email})
        |> render_submit()

      assert html =~ "A new confirmation link has been sent"
      assert Repo.get_by!(Accounts.UserToken, user_id: user.id, context: "confirm")
    end

    test "does not send confirmation token if user is confirmed", %{conn: conn, user: user} do
      Repo.update!(Accounts.User.confirm_changeset(user))

      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      html =
        lv
        |> form("#resend_confirmation_form", user: %{email: user.email})
        |> render_submit()

      assert html =~ "If your email is in our system"

      refute Repo.get_by(Accounts.UserToken, user_id: user.id, context: "confirm")
    end

    test "does not send confirmation token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      html =
        lv
        |> form("#resend_confirmation_form", user: %{email: "unknown@example.com"})
        |> render_submit()

      assert html =~ "If your email is in our system"

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

      # Second attempt: valid token -> succeeds, stays on the page
      result =
        lv
        |> form("#resend_confirmation_form", user: %{"email" => user.email})
        |> render_submit(%{"captcha_token" => "good-token"})

      assert result =~ "If your email is in our system"
      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "confirm"
    end
  end

  defp confirm_token_count(user) do
    Accounts.UserToken
    |> Repo.all()
    |> Enum.count(&(&1.user_id == user.id and &1.context == "confirm"))
  end
end
