defmodule Wasomi.Repo.Migrations.RemoveCaptionsStorageKeyFromLectureOverviewGenerations do
  use Ecto.Migration

  def change do
    alter table(:lecture_overview_generations) do
      remove :captions_storage_key, :string
    end
  end
end
