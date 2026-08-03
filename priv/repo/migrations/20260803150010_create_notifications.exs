defmodule Wasomi.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :kind, :string, null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :read_at, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:notifications, [:user_id, :read_at])

    create constraint(:notifications, :notifications_kind_must_be_valid,
             check: "kind IN ('enrollment_granted')"
           )
  end
end
