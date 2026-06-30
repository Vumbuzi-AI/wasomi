defmodule Wasomi.Repo.Migrations.CreateEnrollments do
  use Ecto.Migration

  def change do
    create table(:enrollments) do
      add :status, :string
      add :enrolled_at, :utc_datetime
      add :activated_at, :utc_datetime
      add :user_id, references(:users, on_delete: :nothing)
      add :course_id, references(:courses, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:enrollments, [:user_id])
    create index(:enrollments, [:course_id])
    create unique_index(:enrollments, [:user_id, :course_id])
  end
end
