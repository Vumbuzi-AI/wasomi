defmodule Wasomi.Repo.Migrations.AddIsFreeToCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :is_free, :boolean, default: false, null: false
      modify :price_minor, :integer, null: true, from: :integer
    end
  end
end
