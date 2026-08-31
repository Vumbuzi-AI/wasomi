defmodule Wasomi.Referrals.Referral do
  use Ecto.Schema
  import Ecto.Changeset

  schema "referrals" do
    field :code, :string
    field :attributed_at, :utc_datetime
    belongs_to :referrer, Wasomi.Accounts.User
    belongs_to :referee, Wasomi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(referral, attrs) do
    referral
    |> cast(attrs, [:referrer_id, :referee_id, :code, :attributed_at])
    |> validate_required([:referrer_id, :referee_id, :code, :attributed_at])
    |> unique_constraint(:referee_id, name: :referrals_referee_id_index)
    |> check_constraint(:referee_id,
      name: :referrals_no_self_referral,
      message: "cannot refer yourself"
    )
    |> assoc_constraint(:referrer)
    |> assoc_constraint(:referee)
  end
end
