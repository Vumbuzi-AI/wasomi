defmodule Wasomi.Repo.Migrations.AddReengagementKindsToNotifications do
  use Ecto.Migration

  def up do
    alter table(:notifications) do
      add :course_id, references(:courses, on_delete: :delete_all)
    end

    create unique_index(:notifications, [:user_id, :course_id, :kind])

    drop constraint(:notifications, :notifications_kind_must_be_valid)

    create constraint(:notifications, :notifications_kind_must_be_valid,
             check: """
             kind IN (
               'enrollment_granted',
               'reengagement_never_started', 'reengagement_never_started_2', 'reengagement_never_started_3',
               'reengagement_gone_quiet', 'reengagement_gone_quiet_2', 'reengagement_gone_quiet_3'
             )
             """
           )
  end

  def down do
    drop constraint(:notifications, :notifications_kind_must_be_valid)

    create constraint(:notifications, :notifications_kind_must_be_valid,
             check: "kind IN ('enrollment_granted')"
           )

    drop unique_index(:notifications, [:user_id, :course_id, :kind])

    alter table(:notifications) do
      remove :course_id
    end
  end
end
