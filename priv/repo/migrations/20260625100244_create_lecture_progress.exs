defmodule Wasomi.Repo.Migrations.CreateLectureProgress do
  use Ecto.Migration

  def change do
    create table(:lecture_progress) do
      add :status, :string
      add :last_position_seconds, :integer
      add :completed_at, :utc_datetime
      add :user_id, references(:users, on_delete: :nothing)
      add :lecture_id, references(:lectures, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:lecture_progress, [:user_id])
    create index(:lecture_progress, [:lecture_id])
    create unique_index(:lecture_progress, [:user_id, :lecture_id])
  end
end
