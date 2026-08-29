defmodule Wasomi.MagicLinkTest do
  use Wasomi.DataCase, async: true

  import Wasomi.AccountsFixtures
  import Swoosh.TestAssertions

  alias Wasomi.Accounts
  alias Wasomi.Accounts.UserToken
  alias Wasomi.Repo

  defp login_tokens(user) do
    Repo.all(from t in UserToken, where: t.user_id == ^user.id and t.context == "login")
  end

  defp backdate_login_tokens(user, seconds_ago) do
    ts = DateTime.utc_now() |> DateTime.add(-seconds_ago, :second) |> DateTime.truncate(:second)

    from(t in UserToken, where: t.user_id == ^user.id and t.context == "login")
    |> Repo.update_all(set: [inserted_at: ts])
  end

  defp request_token(email) do
    :ok = Accounts.deliver_magic_link(email, &"https://t.example/magic/#{&1}")
    assert_received {:email, sent}
    body = sent.text_body || sent.html_body
    [_, token] = Regex.run(~r{https://t\.example/magic/([A-Za-z0-9_-]+)}, body)
    token
  end

  describe "deliver_magic_link/2" do
    test "sends a one-time link for a known address" do
      user = user_fixture()

      assert :ok = Accounts.deliver_magic_link(String.upcase(user.email), &"http://x/#{&1}")

      assert [%UserToken{context: "login", sent_to: sent_to}] = login_tokens(user)
      assert sent_to == user.email
      assert_email_sent(subject: "Your Wasomi login link")
    end

    test "is a silent no-op for an unknown address" do
      assert :ok = Accounts.deliver_magic_link("nobody@example.com", &"http://x/#{&1}")
      assert_no_email_sent()
    end

    test "enforces a short cooldown between sends" do
      user = user_fixture()

      Accounts.deliver_magic_link(user.email, &"http://x/#{&1}")
      Accounts.deliver_magic_link(user.email, &"http://x/#{&1}")

      assert length(login_tokens(user)) == 1

      backdate_login_tokens(user, 120)
      Accounts.deliver_magic_link(user.email, &"http://x/#{&1}")
      assert length(login_tokens(user)) == 2
    end

    test "stops after the hourly cap" do
      user = user_fixture()

      for _ <- 1..5 do
        {_, token} = UserToken.build_email_token(user, "login")
        Repo.insert!(token)
      end

      Accounts.deliver_magic_link(user.email, &"http://x/#{&1}")
      assert length(login_tokens(user)) == 5
    end
  end

  describe "get_user_by_magic_token/1" do
    test "returns the user without consuming the token" do
      user = user_fixture()
      token = request_token(user.email)

      assert Accounts.get_user_by_magic_token(token).id == user.id
      assert Accounts.get_user_by_magic_token(token).id == user.id
      assert length(login_tokens(user)) == 1
    end

    test "returns nil for an expired or malformed token" do
      user = user_fixture()
      token = request_token(user.email)

      assert Accounts.get_user_by_magic_token(token)
      backdate_login_tokens(user, 16 * 60)
      refute Accounts.get_user_by_magic_token(token)
      refute Accounts.get_user_by_magic_token("garbage")
    end
  end

  describe "login_user_by_magic_token/1" do
    test "logs the user in and consumes every login token" do
      user = user_fixture()
      token = request_token(user.email)
      {_, extra} = UserToken.build_email_token(user, "login")
      Repo.insert!(extra)

      assert {:ok, logged_in} = Accounts.login_user_by_magic_token(token)
      assert logged_in.id == user.id
      assert login_tokens(user) == []
      assert Accounts.login_user_by_magic_token(token) == :error
    end

    test "confirms an unconfirmed account on first use" do
      user = user_fixture(confirmed: false)
      refute user.confirmed_at
      token = request_token(user.email)

      assert {:ok, logged_in} = Accounts.login_user_by_magic_token(token)
      assert logged_in.confirmed_at
      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "rejects an expired or malformed token" do
      user = user_fixture()
      token = request_token(user.email)

      backdate_login_tokens(user, 16 * 60)
      assert Accounts.login_user_by_magic_token(token) == :error
      assert Accounts.login_user_by_magic_token("garbage") == :error
    end
  end
end
