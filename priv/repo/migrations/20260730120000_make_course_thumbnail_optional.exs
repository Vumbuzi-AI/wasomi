defmodule Wasomi.Repo.Migrations.MakeCourseThumbnailOptional do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      modify :thumbnail_key, :string, null: true, from: {:string, null: false}
    end
  end
end
