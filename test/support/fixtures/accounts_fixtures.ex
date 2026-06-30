defmodule Wasomi.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Wasomi.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  def unique_user_phone,
    do:
      "2547#{System.unique_integer([:positive]) |> rem(100_000_000) |> Integer.to_string() |> String.pad_leading(8, "0")}"

  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Test User",
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Wasomi.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
