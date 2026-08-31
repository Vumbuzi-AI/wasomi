defmodule Wasomi.Repo.Migrations.AddMessageIdToNotifications do
  use Ecto.Migration

  def change do
    alter table(:notifications) do
      add :channel_message_id, references(:channel_messages, on_delete: :nilify_all)
    end
  end
end
