defmodule Wasomi.Repo.Migrations.AddAttachStatusToLectureOverviewGenerations do
  use Ecto.Migration

  def change do
    alter table(:lecture_overview_generations) do
      add :attach_status, :string, null: false, default: "not_attached"
      add :attach_asset_id, :string
      add :attach_error_message, :text
    end

    create constraint(
             :lecture_overview_generations,
             :lecture_overview_generations_attach_status_must_be_valid,
             check: "attach_status IN ('not_attached', 'attaching', 'attached', 'attach_failed')"
           )
  end
end
