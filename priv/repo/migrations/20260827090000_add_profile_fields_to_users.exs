defmodule Wasomi.Repo.Migrations.AddProfileFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :bio, :text
      add :country, :string
      add :occupation, :string
      add :avatar_key, :string
      add :headline, :string
      add :organization, :string
      add :industry, :string
      add :experience_level, :string
      add :learning_goal, :string
    end
  end
end
