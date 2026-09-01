defmodule Wasomi.Repo.Migrations.AddIsInternalToCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :is_internal, :boolean, null: false, default: false
    end
  end
end
