defmodule Wasomi.Channels.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @max_body 4000

  schema "channel_messages" do
    field :body, :string
    field :kind, Ecto.Enum, values: [:message, :announcement], default: :message
    field :pinned_at, :utc_datetime
    field :deleted_at, :utc_datetime
    field :mentioned_user_ids, {:array, :id}, default: []

    belongs_to :channel, Wasomi.Channels.Channel
    belongs_to :user, Wasomi.Accounts.User
    belongs_to :deleted_by, Wasomi.Accounts.User
    has_many :reactions, Wasomi.Channels.Reaction

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body, :kind, :pinned_at, :channel_id, :user_id, :mentioned_user_ids])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body, :kind, :channel_id, :user_id])
    |> validate_length(:body, min: 1, max: @max_body)
    |> assoc_constraint(:channel)
    |> assoc_constraint(:user)
    |> check_constraint(:body, name: :channel_messages_body_length_ok)
  end

  @doc false
  def delete_changeset(message, %{id: deleted_by_id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    message
    |> change(deleted_at: now, deleted_by_id: deleted_by_id)
  end

  def deleted?(%__MODULE__{deleted_at: nil}), do: false
  def deleted?(%__MODULE__{}), do: true

  def pinned?(%__MODULE__{pinned_at: nil}), do: false
  def pinned?(%__MODULE__{}), do: true
end
