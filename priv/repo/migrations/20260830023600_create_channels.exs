defmodule Wasomi.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  def change do
    create table(:channels) do
      add :course_id, references(:courses, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channels, [:course_id])

    create table(:channel_messages) do
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :body, :text, null: false
      add :kind, :string, null: false, default: "message"
      add :pinned_at, :utc_datetime
      add :deleted_at, :utc_datetime
      add :deleted_by_id, references(:users, on_delete: :nilify_all)
      add :mentioned_user_ids, {:array, :id}, null: false, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create index(:channel_messages, [:channel_id, :inserted_at])

    create constraint(:channel_messages, :channel_messages_kind_must_be_valid,
             check: "kind IN ('message', 'announcement')"
           )

    create constraint(:channel_messages, :channel_messages_body_length_ok,
             check: "char_length(btrim(body)) BETWEEN 1 AND 4000"
           )

    create table(:channel_reads) do
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :last_read_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:channel_reads, [:channel_id, :user_id])
  end
end
