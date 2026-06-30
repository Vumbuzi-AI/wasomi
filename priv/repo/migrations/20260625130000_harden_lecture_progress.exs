defmodule Wasomi.Repo.Migrations.HardenLectureProgress do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE lecture_progress
    SET status = COALESCE(status, 'not_started'),
        last_position_seconds = GREATEST(COALESCE(last_position_seconds, 0), 0),
        completed_at = CASE
          WHEN status = 'completed' THEN COALESCE(completed_at, updated_at, NOW())
          ELSE NULL
        END
    """)

    alter table(:lecture_progress) do
      modify :status, :string, null: false, default: "not_started"
      modify :last_position_seconds, :integer, null: false, default: 0

      modify :user_id, references(:users, on_delete: :delete_all),
        null: false,
        from: references(:users, on_delete: :nothing)

      modify :lecture_id, references(:lectures, on_delete: :delete_all),
        null: false,
        from: references(:lectures, on_delete: :nothing)
    end

    create constraint(:lecture_progress, :lecture_progress_status_must_be_valid,
             check: "status IN ('not_started', 'in_progress', 'completed')"
           )

    create constraint(:lecture_progress, :lecture_progress_position_must_be_non_negative,
             check: "last_position_seconds >= 0"
           )
  end

  def down do
    drop constraint(:lecture_progress, :lecture_progress_position_must_be_non_negative)
    drop constraint(:lecture_progress, :lecture_progress_status_must_be_valid)

    alter table(:lecture_progress) do
      modify :status, :string, null: true, default: nil
      modify :last_position_seconds, :integer, null: true, default: nil

      modify :user_id, references(:users, on_delete: :nothing),
        null: true,
        from: references(:users, on_delete: :delete_all)

      modify :lecture_id, references(:lectures, on_delete: :nothing),
        null: true,
        from: references(:lectures, on_delete: :delete_all)
    end
  end
end
