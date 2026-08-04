defmodule Wasomi.Repo.Migrations.CreateEnrollmentAudits do
  use Ecto.Migration

  def change do
    create table(:enrollment_audits) do
      add :reason, :text, null: false
      add :enrollment_id, references(:enrollments, on_delete: :delete_all), null: false
      add :admin_user_id, references(:users, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:enrollment_audits, [:enrollment_id])
    create index(:enrollment_audits, [:admin_user_id])

    create constraint(:enrollment_audits, :enrollment_audits_reason_must_be_present,
             check: "length(trim(reason)) > 0"
           )
  end
end
