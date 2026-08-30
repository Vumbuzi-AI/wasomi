defmodule Wasomi.Channels.Read do
  use Ecto.Schema
  import Ecto.Changeset

  schema "channel_reads" do
    field :last_read_at, :utc_datetime_usec
    belongs_to :channel, Wasomi.Channels.Channel
    belongs_to :user, Wasomi.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(read, attrs) do
    read
    |> cast(attrs, [:channel_id, :user_id, :last_read_at])
    |> validate_required([:channel_id, :user_id, :last_read_at])
    |> unique_constraint([:channel_id, :user_id])
  end
end
