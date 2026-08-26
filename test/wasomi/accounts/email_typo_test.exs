defmodule Wasomi.Accounts.EmailTypoTest do
  use ExUnit.Case, async: true

  alias Wasomi.Accounts.EmailTypo

  describe "suggest/1" do
    test "suggests a correction for a close misspelling of a popular domain" do
      assert EmailTypo.suggest("user@gmial.com") == {:ok, "user@gmail.com"}
      assert EmailTypo.suggest("user@yaho.com") == {:ok, "user@yahoo.com"}
      assert EmailTypo.suggest("user@hotmial.com") == {:ok, "user@hotmail.com"}
      assert EmailTypo.suggest("user@livee.com") == {:ok, "user@live.com"}
    end

    test "keeps the local part unchanged in the suggestion" do
      assert EmailTypo.suggest("jane.doe+work@gmial.com") == {:ok, "jane.doe+work@gmail.com"}
    end

    test "returns :none for an exact match of a popular domain" do
      for domain <- ~w(gmail.com yahoo.com outlook.com hotmail.com icloud.com live.com aol.com
                       proton.me protonmail.com msn.com) do
        assert EmailTypo.suggest("user@#{domain}") == :none
      end
    end

    test "is case-insensitive when matching the domain" do
      assert EmailTypo.suggest("user@GMIAL.COM") == {:ok, "user@gmail.com"}
      assert EmailTypo.suggest("user@Gmail.com") == :none
    end

    test "returns :none for a domain that doesn't closely resemble any popular domain" do
      assert EmailTypo.suggest("user@customdomain.org") == :none
      assert EmailTypo.suggest("user@wasomi.africa") == :none
    end

    test "returns :none for malformed input" do
      assert EmailTypo.suggest("invalid-email") == :none
      assert EmailTypo.suggest("") == :none
      assert EmailTypo.suggest("@gmial.com") == :none
      assert EmailTypo.suggest("user@") == :none
      assert EmailTypo.suggest(nil) == :none
    end

    test "trims surrounding whitespace before matching" do
      assert EmailTypo.suggest("  user@gmial.com  ") == {:ok, "user@gmail.com"}
    end

    test "picks the closest domain when a typo is ambiguous between two candidates" do
      assert EmailTypo.suggest("user@livee.com") == {:ok, "user@live.com"}
    end

    test "does not suggest a correction for noise below the similarity threshold" do
      assert EmailTypo.suggest("user@msnn.com") == {:ok, "user@msn.com"}
      assert EmailTypo.suggest("user@mmznn.com") == :none
    end

    test "short domains can still false-positive against an unrelated short domain" do
      # accepted limitation, not a bug
      assert EmailTypo.suggest("user@min.com") == {:ok, "user@msn.com"}
    end
  end
end
