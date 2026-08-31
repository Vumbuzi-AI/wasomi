defmodule Wasomi.Repo.Migrations.AddPublicProfileFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :public_profile_enabled, :boolean, null: false, default: false
      add :public_profile_slug, :string
      add :linkedin_url, :string
    end

    create unique_index(:users, [:public_profile_slug],
             where: "public_profile_slug IS NOT NULL",
             name: :users_public_profile_slug_unique_index
           )
  end
end
