defmodule Wasomi.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notifications" do
    field :kind, Ecto.Enum, values: [:enrollment_granted]
    field :title, :string
    field :body, :string
    field :read_at, :utc_datetime
    belongs_to :user, Wasomi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:kind, :title, :body, :read_at, :user_id])
    |> validate_required([:kind, :title, :body, :user_id])
    |> assoc_constraint(:user)
  end
end
