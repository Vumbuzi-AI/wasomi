defmodule Wasomi.Repo.Migrations.CreateLectures do
  use Ecto.Migration

  def change do
    create table(:lectures) do
      add :title, :string
      add :description, :text
      add :video_provider, :string
      add :video_asset_id, :string
      add :duration_seconds, :integer
      add :position, :integer
      add :module_id, references(:modules, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:lectures, [:module_id])
    create unique_index(:lectures, [:module_id, :position])
  end
end
