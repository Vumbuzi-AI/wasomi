defmodule Wasomi.Repo.Migrations.CreateModules do
  use Ecto.Migration

  def change do
    create table(:modules) do
      add :title, :string
      add :description, :text
      add :position, :integer
      add :course_id, references(:courses, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:modules, [:course_id])
    create unique_index(:modules, [:course_id, :position])
  end
end
