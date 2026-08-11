defmodule Wasomi.Repo.Migrations.RemoveCourseSubtitle do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      remove :subtitle, :string, null: false
    end
  end
end
