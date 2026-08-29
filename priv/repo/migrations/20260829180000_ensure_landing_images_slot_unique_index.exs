defmodule Wasomi.Repo.Migrations.EnsureLandingImagesSlotUniqueIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists unique_index(:landing_images, [:slot])
  end
end
