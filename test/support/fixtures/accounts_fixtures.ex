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
    attrs =
      Enum.into(attrs, %{
        name: "Test User",
        email: unique_user_email(),
        password: valid_user_password()
      })

    Map.put_new(attrs, :password_confirmation, attrs.password)
  end

  @doc """
  Registers a test user, confirmed by default (`confirmed: false` to opt
  out) — most tests care about something other than confirmation status,
  and email-confirmation enforcement means an unconfirmed user can't reach
  most routes.
  """
  def user_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    {confirmed?, attrs} = Map.pop(attrs, :confirmed, true)

    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Wasomi.Accounts.register_user()

    if confirmed?, do: confirm_user_fixture(user), else: user
  end

  defp confirm_user_fixture(user) do
    user
    |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Wasomi.Repo.update!()
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
