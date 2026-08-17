defmodule Wasomi.Repo.Migrations.AddCaptionsStorageKeyToLectureOverviewGenerations do
  use Ecto.Migration

  def change do
    alter table(:lecture_overview_generations) do
      add :captions_storage_key, :string
    end
  end
end
