defmodule WasomiWeb.WelcomeLiveTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures

  alias Wasomi.Accounts

  describe "GET /welcome" do
    test "a not-yet-onboarded learner is routed here from any learner route", %{conn: conn} do
      conn = log_in_user(conn, user_fixture(onboarded: false))

      assert {:error, {:redirect, %{to: "/welcome"}}} = live(conn, ~p"/dashboard")
    end

    test "renders the one-time onboarding form", %{conn: conn} do
      user = user_fixture(onboarded: false)
      {:ok, lv, html} = live(log_in_user(conn, user), ~p"/welcome")

      assert html =~ "Welcome to Wasomi, #{user.first_name}."
      assert html =~ "What brings you to Wasomi?"
      # Skip is present but withheld (faded out) until the learner engages.
      assert html =~ ~s(data-skip-available="false")

      assert lv
             |> form("#welcome_form", user: %{"experience_level" => "mid"})
             |> render_change() =~ ~s(data-skip-available="true")
    end

    test "an already-onboarded learner is bounced to the dashboard", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      assert {:error, {:live_redirect, %{to: "/dashboard"}}} = live(conn, ~p"/welcome")
    end
  end

  describe "submitting" do
    setup %{conn: conn} do
      user = user_fixture(onboarded: false)
      %{conn: log_in_user(conn, user), user: user}
    end

    test "saving persists the answers, marks onboarding done, and continues to the dashboard", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/welcome")

      # `country` rides on a JS-driven hidden input, so dispatch the event
      # directly (as the picker's own JS would) rather than through `form/3`.
      assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
               render_submit(lv, "save", %{
                 "user" => %{
                   "learning_goal" => "upskilling",
                   "experience_level" => "mid",
                   "country" => "Kenya"
                 }
               })

      updated = Accounts.get_user!(user.id)
      assert updated.learning_goal == :upskilling
      assert updated.experience_level == :mid
      assert updated.country == "Kenya"
      assert Accounts.onboarding_completed?(updated)
    end

    test "offers an optional gender select and persists the choice", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/welcome")

      assert html =~ "Gender"
      assert html =~ "Prefer not to say"

      assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
               render_submit(lv, "save", %{"user" => %{"gender" => "female"}})

      assert Accounts.get_user!(user.id).gender == :female
    end

    test "skipping marks onboarding done without saving answers", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/welcome")

      send(lv.pid, :reveal_skip)
      assert render(lv) =~ ~s(data-skip-available="true")

      assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
               lv |> element("button", "Skip for now") |> render_click()

      updated = Accounts.get_user!(user.id)
      assert Accounts.onboarding_completed?(updated)
      assert is_nil(updated.learning_goal)
    end

    test "after onboarding, learner routes load normally", %{conn: conn, user: user} do
      {:ok, _} = Accounts.complete_user_onboarding(user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Wasomi"
    end
  end
end
