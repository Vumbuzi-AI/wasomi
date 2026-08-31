defmodule Wasomi.Repo.Migrations.AddHeroMultiImageToLandingImages do
  use Ecto.Migration

  # Every slot except :hero still holds exactly one row; :hero can hold
  # several, ordered by :position.
  def change do
    alter table(:landing_images) do
      add :position, :integer, null: false, default: 0
    end

    drop unique_index(:landing_images, [:slot])

    create unique_index(:landing_images, [:slot],
             where: "slot != 'hero'",
             name: :landing_images_single_slot_index
           )

    create unique_index(:landing_images, [:slot, :position])
  end
end
