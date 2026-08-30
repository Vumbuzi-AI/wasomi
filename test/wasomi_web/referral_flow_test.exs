defmodule WasomiWeb.ReferralFlowTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures

  alias Wasomi.{Accounts, Repo}
  alias Wasomi.Referrals.Referral

  describe "GET /join" do
    test "stores the ref and sends an anonymous visitor to register", %{conn: conn} do
      referrer = user_fixture()

      conn = get(conn, ~p"/join?ref=#{referrer.referral_code}")

      assert redirected_to(conn) == ~p"/users/register"
      assert get_session(conn, :referral_ref) == referrer.referral_code
      assert %{"_wasomi_referral" => _} = conn.resp_cookies
    end

    test "sends a signed-in learner to their dashboard", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/join?ref=WHATEVER")
      assert redirected_to(conn) == ~p"/dashboard"
    end
  end

  describe "registration attribution" do
    test "a signup after visiting /join?ref= is attributed to the referrer", %{conn: conn} do
      referrer = user_fixture()
      email = unique_user_email()

      {:ok, lv, _html} =
        conn
        |> get(~p"/join?ref=#{referrer.referral_code}")
        |> recycle()
        |> live(~p"/users/register")

      lv
      |> form("#registration_form",
        user: valid_user_attributes(email: email, name: "New Learner")
      )
      |> render_submit()

      referee = Accounts.get_user_by_email(email)
      assert %Referral{referrer_id: rid} = Repo.get_by(Referral, referee_id: referee.id)
      assert rid == referrer.id
    end

    test "a signup with no referral link is not attributed", %{conn: conn} do
      email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      lv
      |> form("#registration_form", user: valid_user_attributes(email: email, name: "Solo"))
      |> render_submit()

      referee = Accounts.get_user_by_email(email)
      assert Repo.get_by(Referral, referee_id: referee.id) == nil
    end
  end
end
