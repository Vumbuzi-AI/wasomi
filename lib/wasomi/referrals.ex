defmodule Wasomi.Referrals do
  @moduledoc """
  First-version student referrals: attribution and reporting only, no
  rewards, discounts, or thresholds (see PLANNING_STUDENT_REFERRALS_REWARDS.md).

  A learner shares `link_for/1` (`/join?ref=CODE`). When a referred visitor
  registers, `attribute/2` records a one-time `Referral` linking them to the
  referrer. The funnel is then reported on read: signups → confirmed email →
  first active enrollment.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Wasomi.Accounts
  alias Wasomi.Accounts.User
  alias Wasomi.Enrollments.Enrollment
  alias Wasomi.Referrals.Referral
  alias Wasomi.Repo

  # Throwaway-mailbox providers. Not exhaustive — enough to blunt casual
  # count-inflation without a live disposable-email API.
  @disposable_domains MapSet.new(~w(
                          mailinator.com guerrillamail.com guerrillamail.info sharklasers.com
                          10minutemail.com 10minutemail.net temp-mail.org tempmail.com tempr.email
                          yopmail.com yopmail.net trashmail.com trashmail.de getnada.com nada.email
                          dispostable.com maildrop.cc mailnesia.com mytemp.email throwawaymail.com
                          fakeinbox.com mohmal.com emailondeck.com moakt.com tempmailo.com
                          discard.email discardmail.com spamgourmet.com spam4.me mailcatch.com
                          burnermail.io mailsac.com inboxbear.com tempmail.plus fake-mail.pro
                        ))

  @doc "The shareable referral URL for a learner."
  def link_for(%User{referral_code: code}) when is_binary(code) do
    "#{WasomiWeb.Endpoint.url()}/join?ref=#{code}"
  end

  @doc """
  Attributes `referee` to the owner of `code`. Best-effort and idempotent —
  a no-op (`{:ok, :skipped}`) when the code is unknown, self-referring, the
  referee is already attributed, the referee's email is disposable, or the
  referrer has hit the rolling 24h attribution cap.
  """
  def attribute(%User{} = referee, code) do
    with %User{} = referrer <- Accounts.get_user_by_referral_code(to_string(code || "")),
         true <- referrer.id != referee.id,
         nil <- Repo.get_by(Referral, referee_id: referee.id),
         :ok <- check_disposable(referee),
         :ok <- check_daily_cap(referrer) do
      insert_attribution(referrer, referee, referrer.referral_code)
    else
      _ -> {:ok, :skipped}
    end
  end

  defp check_disposable(%User{email: email}) do
    domain = email |> to_string() |> String.split("@") |> List.last() |> String.downcase()

    if MapSet.member?(@disposable_domains, domain) do
      Logger.info("AUDIT event=REFERRAL.SKIPPED_DISPOSABLE referee_domain=#{domain}")
      :skip
    else
      :ok
    end
  end

  defp check_daily_cap(%User{id: referrer_id, email: email}) do
    cap = Application.get_env(:wasomi, :referral_daily_cap, 25)
    since = DateTime.utc_now() |> DateTime.add(-24, :hour) |> DateTime.truncate(:second)

    recent =
      Referral
      |> where([r], r.referrer_id == ^referrer_id and r.inserted_at > ^since)
      |> Repo.aggregate(:count)

    if recent >= cap do
      Logger.warning(
        "AUDIT event=REFERRAL.SKIPPED_RATE_LIMITED referrer_domain=#{domain(email)} count=#{recent}"
      )

      :skip
    else
      :ok
    end
  end

  defp insert_attribution(referrer, referee, code) do
    %Referral{}
    |> Referral.changeset(%{
      referrer_id: referrer.id,
      referee_id: referee.id,
      code: code,
      attributed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert()
    |> case do
      {:ok, referral} ->
        log("ATTRIBUTED", referrer, referee)
        {:ok, referral}

      # Lost a race to another concurrent signup for the same referee.
      {:error, %Ecto.Changeset{errors: [{:referee_id, _} | _]}} ->
        {:ok, :skipped}

      {:error, changeset} ->
        Logger.error(
          "Referral attribution failed for referee #{referee.id}: #{inspect(changeset)}"
        )

        {:error, changeset}
    end
  end

  @doc "The learner who referred `user`, or `nil`."
  def referred_by(%User{id: id}), do: Map.get(referrers_of([id]), id)

  @doc "Map of `referee_id => referrer %User{}` for the given referee ids."
  def referrers_of([]), do: %{}

  def referrers_of(referee_ids) when is_list(referee_ids) do
    Referral
    |> where([r], r.referee_id in ^referee_ids)
    |> join(:inner, [r], u in User, on: u.id == r.referrer_id)
    |> select([r, u], {r.referee_id, u})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  The referral funnel for one referrer:

    * `:signups`   — referred accounts created
    * `:confirmed` — of those, with a confirmed email
    * `:converted` — of those, with at least one active enrollment
  """
  def stats_for(%User{id: id}), do: Map.get(counts_by_referrer([id]), id, zero_stats())

  @doc """
  `stats_for/1` for many referrers at once, keyed by referrer id. Ids with
  no referrals are omitted.
  """
  def counts_by_referrer([]), do: %{}

  def counts_by_referrer(referrer_ids) when is_list(referrer_ids) do
    Referral
    |> where([r], r.referrer_id in ^referrer_ids)
    |> join(:inner, [r], u in User, on: u.id == r.referee_id)
    |> join(:left, [r, u], e in Enrollment, on: e.user_id == u.id and e.status == :active)
    |> group_by([r], r.referrer_id)
    |> select([r, u, e], %{
      referrer_id: r.referrer_id,
      signups: count(u.id, :distinct),
      confirmed:
        count(fragment("CASE WHEN ? IS NOT NULL THEN ? END", u.confirmed_at, u.id), :distinct),
      converted: count(e.user_id, :distinct)
    })
    |> Repo.all()
    |> Map.new(fn row -> {row.referrer_id, Map.delete(row, :referrer_id)} end)
  end

  defp zero_stats, do: %{signups: 0, confirmed: 0, converted: 0}

  @doc "The accounts `user` has referred, referee preloaded, newest first."
  def list_referred(%User{id: id}) do
    Referral
    |> where([r], r.referrer_id == ^id)
    |> order_by([r], desc: r.attributed_at, desc: r.id)
    |> preload(:referee)
    |> Repo.all()
  end

  defp log(event, referrer, referee) do
    Logger.info(
      "AUDIT event=REFERRAL.#{event} referrer_domain=#{domain(referrer.email)} " <>
        "referee_domain=#{domain(referee.email)}"
    )
  end

  defp domain(email), do: email |> to_string() |> String.split("@") |> List.last()
end
