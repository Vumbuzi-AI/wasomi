defmodule Wasomi.Repo.Migrations.CreateAccountAuditEvents do
  use Ecto.Migration

  def change do
    create table(:account_audit_events) do
      add :event, :string, null: false
      add :metadata, :map, null: false, default: %{}
      add :ip_address, :string, size: 128
      add :user_agent, :string, size: 512
      add :request_id, :string, size: 64
      # `user_id` is the subject of the event; `actor_id` is who performed it
      # when different (an admin acting on a learner). Both nil out rather
      # than cascade so the trail survives account deletion.
      add :user_id, references(:users, on_delete: :nilify_all)
      add :actor_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:account_audit_events, [:user_id, :inserted_at])
    create index(:account_audit_events, [:event, :inserted_at])
    create index(:account_audit_events, [:actor_id])

    # Matches the house style (users_role_must_be_valid,
    # lecture_progress_status_must_be_valid): the DB rejects unknown event
    # names, so nothing that bypasses Wasomi.Accounts.AuditEvent.changeset/2
    # can pollute the trail. Keep in sync with AuditEvent.event_values/0.
    create constraint(:account_audit_events, :account_audit_events_event_must_be_valid,
             check: """
             event IN (
               'login_succeeded', 'login_failed', 'logout', 'registered',
               'email_confirmed', 'email_changed', 'password_changed',
               'password_reset', 'profile_updated', 'role_changed'
             )
             """
           )
  end
end
