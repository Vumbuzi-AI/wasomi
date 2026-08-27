defmodule WasomiWeb.UserRegistrationLiveTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Swoosh.TestAssertions

  alias Wasomi.Accounts.UserToken
  alias Wasomi.Repo

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Register"
      assert html =~ "Log in"
    end

    test "prefills name and email from query params", %{conn: conn} do
      {:ok, _lv, html} =
        live(conn, ~p"/users/register?name=Jane%20Doe&email=jane@example.com")

      assert html =~ "Jane Doe"
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
