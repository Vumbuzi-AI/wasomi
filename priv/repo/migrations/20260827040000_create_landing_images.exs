defmodule Wasomi.Repo.Migrations.CreateLandingImages do
  use Ecto.Migration

  def change do
    create table(:landing_images) do
      add :slot, :string, null: false
      add :image_url, :string, null: false
      add :alt_text, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:landing_images, [:slot])
  end
end
