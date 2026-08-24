defmodule Wasomi.Repo.Migrations.CreateResourceProgress do
  use Ecto.Migration

  def change do
    # A video reports its own position, so `lecture_progress` can decide when a
    # recording has been watched. A PDF reports nothing — the browser gives us no
    # trustworthy "they read it" signal — so reading is an explicit learner
    # action, one row per learner per resource, written when they click
    # "Mark as read". A lecture whose only material is PDFs is complete once
    # every one of its PDFs has a row here.
    create table(:resource_progress) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :lecture_resource_id, references(:lecture_resources, on_delete: :delete_all),
        null: false

      add :completed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:resource_progress, [:user_id, :lecture_resource_id])
    create index(:resource_progress, [:lecture_resource_id])
  end
end

