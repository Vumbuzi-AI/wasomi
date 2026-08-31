defmodule Wasomi.ReferralsTest do
  # not async: the rate-cap test mutates the global :referral_daily_cap
  use Wasomi.DataCase, async: false

  import Wasomi.{AccountsFixtures, CatalogFixtures, EnrollmentsFixtures}

  alias Wasomi.{Accounts, Referrals}
  alias Wasomi.Referrals.Referral

  describe "attribute/2" do
    test "links a new referee to the code's owner" do
      referrer = user_fixture()
      referee = user_fixture()

      assert {:ok, %Referral{} = ref} = Referrals.attribute(referee, referrer.referral_code)
      assert ref.referrer_id == referrer.id
      assert ref.referee_id == referee.id
      assert ref.code == referrer.referral_code
    end

    test "is a no-op for a self-referral" do
      user = user_fixture()
      assert {:ok, :skipped} = Referrals.attribute(user, user.referral_code)
      assert Repo.get_by(Referral, referee_id: user.id) == nil
    end

    test "is a no-op for an unknown or blank code" do
      referee = user_fixture()
      assert {:ok, :skipped} = Referrals.attribute(referee, "NOPECODE")
      assert {:ok, :skipped} = Referrals.attribute(referee, nil)
      assert {:ok, :skipped} = Referrals.attribute(referee, "")
      assert Repo.get_by(Referral, referee_id: referee.id) == nil
    end

    test "keeps the first attribution; a later code is ignored" do
      first = user_fixture()
      second = user_fixture()
      referee = user_fixture()

      assert {:ok, %Referral{}} = Referrals.attribute(referee, first.referral_code)
      assert {:ok, :skipped} = Referrals.attribute(referee, second.referral_code)

      assert %Referral{referrer_id: rid} = Repo.get_by(Referral, referee_id: referee.id)
      assert rid == first.id
    end

    test "does not credit a referee signing up with a disposable email" do
      referrer = user_fixture()

      referee =
        user_fixture(%{email: "burner#{System.unique_integer([:positive])}@mailinator.com"})

      assert {:ok, :skipped} = Referrals.attribute(referee, referrer.referral_code)
      assert Repo.get_by(Referral, referee_id: referee.id) == nil
    end

    test "stops crediting a referrer past the rolling 24h cap" do
      prev = Application.get_env(:wasomi, :referral_daily_cap)
      Application.put_env(:wasomi, :referral_daily_cap, 2)
      on_exit(fn -> Application.put_env(:wasomi, :referral_daily_cap, prev) end)

      referrer = user_fixture()
      a = user_fixture()
      b = user_fixture()
      c = user_fixture()

      assert {:ok, %Referral{}} = Referrals.attribute(a, referrer.referral_code)
      assert {:ok, %Referral{}} = Referrals.attribute(b, referrer.referral_code)
      assert {:ok, :skipped} = Referrals.attribute(c, referrer.referral_code)

      assert Repo.get_by(Referral, referee_id: c.id) == nil
    end
  end

  describe "link_for/1" do
    test "is /join?ref=CODE" do
      user = user_fixture()
      assert Referrals.link_for(user) =~ "/join?ref=#{user.referral_code}"
    end
  end

  describe "stats_for/1 funnel" do
    test "counts signups, confirmed emails, and active enrollments separately" do
      referrer = user_fixture()

      unconfirmed = user_fixture(confirmed: false)
      confirmed = user_fixture()
      enrolled = user_fixture()

      for u <- [unconfirmed, confirmed, enrolled],
          do: {:ok, _} = Referrals.attribute(u, referrer.referral_code)

      course = course_fixture(status: :published)
      enrollment_fixture(user_id: enrolled.id, course_id: course.id, status: :active)

      assert %{signups: 3, confirmed: 2, converted: 1} = Referrals.stats_for(referrer)
    end

    test "is zero for someone with no referrals" do
      assert %{signups: 0, confirmed: 0, converted: 0} = Referrals.stats_for(user_fixture())
    end
  end

  test "referred_by/1 and list_referred/1" do
    referrer = user_fixture(%{name: "Jane"})
    a = user_fixture()
    b = user_fixture()

    {:ok, _} = Referrals.attribute(a, referrer.referral_code)
    {:ok, _} = Referrals.attribute(b, referrer.referral_code)

    assert Referrals.referred_by(a).id == referrer.id
    assert Referrals.referred_by(referrer) == nil

    assert Referrals.list_referred(referrer) |> Enum.map(& &1.referee_id) |> Enum.sort() ==
             Enum.sort([a.id, b.id])
  end

  test "registration generates a unique referral code for every user" do
    a = user_fixture()
    b = user_fixture()

    assert a.referral_code =~ ~r/^[A-Z2-7]{8}$/
    assert a.referral_code != b.referral_code
    assert Accounts.get_user_by_referral_code(a.referral_code).id == a.id
  end
end
