defmodule Wasomi.Accounts.EmailTypo do
  @moduledoc """
  Pure helper module for detecting and suggesting corrections for common email domain typos.

  Uses `String.jaro_distance/2` — the same similarity function Elixir itself
  uses for "did you mean?" suggestions — to detect close misspellings of
  popular email domains (e.g., `gmial.com` -> `gmail.com`, `yaho.com` ->
  `yahoo.com`) without network or database overhead.
  """

  @popular_domains [
    "gmail.com",
    "yahoo.com",
    "outlook.com",
    "hotmail.com",
    "icloud.com",
    "live.com",
    "proton.me",
    "protonmail.com",
    "msn.com"
  ]

  # Real typos score >= 0.90; short domains (e.g. "msn.com") can still
  # false-positive against an unrelated short domain.
  @similarity_threshold 0.90

  @doc """
  Suggests a corrected email address if the domain part closely matches a known popular domain.

  Returns `{:ok, suggested_email}` if a likely typo is detected, or `:none` if the email
  is valid, exact match, or does not closely resemble any known domain.

  ## Examples

      iex> Wasomi.Accounts.EmailTypo.suggest("user@gmial.com")
      {:ok, "user@gmail.com"}

      iex> Wasomi.Accounts.EmailTypo.suggest("user@gmail.com")
      :none

      iex> Wasomi.Accounts.EmailTypo.suggest("user@customdomain.org")
      :none

      iex> Wasomi.Accounts.EmailTypo.suggest("invalid-email")
      :none
  """
  @spec suggest(String.t() | nil) :: {:ok, String.t()} | :none
  def suggest(email) when is_binary(email) do
    email = String.trim(email)

    case String.split(email, "@", parts: 2) do
      [local_part, domain] when byte_size(local_part) > 0 and byte_size(domain) > 0 ->
        domain = String.downcase(domain)

        if domain in @popular_domains do
          :none
        else
          find_closest_domain(domain, local_part)
        end

      _ ->
        :none
    end
  end

  def suggest(_), do: :none

  defp find_closest_domain(domain, local_part) do
    matches =
      for target_domain <- @popular_domains,
          score = String.jaro_distance(domain, target_domain),
          score >= @similarity_threshold,
          do: {score, target_domain}

    case Enum.max_by(matches, fn {score, _} -> score end, fn -> nil end) do
      {_score, best_domain} -> {:ok, "#{local_part}@#{best_domain}"}
      nil -> :none
    end
  end
end
