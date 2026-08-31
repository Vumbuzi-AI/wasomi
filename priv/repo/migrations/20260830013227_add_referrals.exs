defmodule Wasomi.Repo.Migrations.AddReferrals do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :referral_code, :string
    end

    flush()
    backfill_referral_codes()

    create unique_index(:users, [:referral_code])

    create table(:referrals) do
      add :referrer_id, references(:users, on_delete: :delete_all), null: false
      add :referee_id, references(:users, on_delete: :delete_all), null: false
      add :code, :string, null: false
      add :attributed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    # One referrer per referee — attribution is set once and never overwritten.
    create unique_index(:referrals, [:referee_id])
    create index(:referrals, [:referrer_id])

    create constraint(:referrals, :referrals_no_self_referral, check: "referrer_id <> referee_id")
  end

  def down do
    drop table(:referrals)
    drop unique_index(:users, [:referral_code])

    alter table(:users) do
      remove :referral_code
    end
  end

  defp backfill_referral_codes do
    taken =
      repo().query!("SELECT referral_code FROM users WHERE referral_code IS NOT NULL").rows
      |> List.flatten()
      |> MapSet.new()

    {ids, _taken} =
      repo().query!("SELECT id FROM users WHERE referral_code IS NULL").rows
      |> List.flatten()
      |> Enum.map_reduce(taken, fn id, taken ->
        code = unique_code(taken)
        {{id, code}, MapSet.put(taken, code)}
      end)

    Enum.each(ids, fn {id, code} ->
      repo().query!("UPDATE users SET referral_code = $1 WHERE id = $2", [code, id])
    end)
  end

  defp unique_code(taken) do
    code = 5 |> :crypto.strong_rand_bytes() |> Base.encode32(padding: false)
    if MapSet.member?(taken, code), do: unique_code(taken), else: code
  end
end
