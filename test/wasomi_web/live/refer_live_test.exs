defmodule WasomiWeb.ReferLiveTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Wasomi.{AccountsFixtures, CatalogFixtures, EnrollmentsFixtures}

  alias Wasomi.Referrals

  test "redirects an anonymous visitor to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, ~p"/refer")
  end

  test "shows the referral link and funnel counts", %{conn: conn} do
    referrer = user_fixture()
    joined = user_fixture()
    started = user_fixture()

    {:ok, _} = Referrals.attribute(joined, referrer.referral_code)
    {:ok, _} = Referrals.attribute(started, referrer.referral_code)
    course = course_fixture(status: :published)
    enrollment_fixture(user_id: started.id, course_id: course.id, status: :active)

    {:ok, _lv, html} = conn |> log_in_user(referrer) |> live(~p"/refer")

    assert html =~ "Refer a friend"
    assert html =~ "/join?ref=#{referrer.referral_code}"
    assert html =~ ~s(data-copy=")
    assert html =~ "friends joined"
    assert html =~ "started learning"
    assert html =~ ">2</p>"
    assert html =~ ">1</p>"
  end
end
