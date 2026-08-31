defmodule Wasomi.Repo.Migrations.CreateChannelMessageReactions do
  use Ecto.Migration

  def change do
    create table(:channel_message_reactions) do
      add :message_id, references(:channel_messages, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :emoji, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channel_message_reactions, [:message_id, :user_id, :emoji])
    create index(:channel_message_reactions, [:message_id])

    create constraint(:channel_message_reactions, :channel_message_reactions_emoji_length_ok,
             check: "char_length(emoji) BETWEEN 1 AND 16"
           )
  end
end
