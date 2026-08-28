defmodule Wasomi.Repo.Migrations.AllowLecturesWithoutVideo do
  use Ecto.Migration

  # A lecture can now exist with resources (documents/links) instead of a
  # video — video_provider/video_asset_id/duration_seconds become optional
  # at the DB level, matching the same relaxation on Lecture.changeset/2.
  # The existing check constraints (duration > 0, video_provider IN (...))
  # need no change: a SQL CHECK constraint already passes automatically on
  # a NULL value, only firing once a value is actually present.
  def change do
    alter table(:lectures) do
      modify :video_provider, :string, null: true
      modify :video_asset_id, :string, null: true
      modify :duration_seconds, :integer, null: true
    end
  end
end
