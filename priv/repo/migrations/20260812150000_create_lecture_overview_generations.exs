defmodule Wasomi.Repo.Migrations.CreateLectureOverviewGenerations do
  use Ecto.Migration

  def change do
    create table(:lecture_overview_generations) do
      add :lecture_id, references(:lectures, on_delete: :delete_all), null: false
      add :requested_by_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :error_message, :text
      add :scene_count, :integer
      add :video_storage_key, :string

      timestamps(type: :utc_datetime)
    end

    create index(:lecture_overview_generations, [:lecture_id])

    create constraint(
             :lecture_overview_generations,
             :lecture_overview_generations_status_must_be_valid,
             check: "status IN ('pending', 'processing', 'ready', 'failed')"
           )
  end
end
