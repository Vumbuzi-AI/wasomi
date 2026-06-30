defmodule Wasomi.Repo.Migrations.CreateCourses do
  use Ecto.Migration

  def change do
    create table(:courses) do
      add :slug, :string
      add :title, :string
      add :subtitle, :string
      add :description, :text
      add :thumbnail_key, :string
      add :price_minor, :integer
      add :currency, :string, default: "KES"
      add :status, :string
      add :position, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:courses, [:slug])
  end
end
