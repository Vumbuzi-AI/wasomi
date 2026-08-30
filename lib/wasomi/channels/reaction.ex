defmodule Wasomi.Channels.Reaction do
  use Ecto.Schema
  import Ecto.Changeset

  @allowed ~w(👍 ❤️ 😂 🎉 🙌 👀 🔥 ✅)

  schema "channel_message_reactions" do
    field :emoji, :string
    belongs_to :message, Wasomi.Channels.Message
    belongs_to :user, Wasomi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def allowed, do: @allowed

  @doc false
  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:emoji, :message_id, :user_id])
    |> validate_required([:emoji, :message_id, :user_id])
    |> validate_inclusion(:emoji, @allowed)
    |> assoc_constraint(:message)
    |> assoc_constraint(:user)
    |> unique_constraint([:message_id, :user_id, :emoji])
  end
end
