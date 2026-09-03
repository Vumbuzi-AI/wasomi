defmodule Wasomi.Repo.Migrations.AddActiveModeChangedToAccountAuditEvents do
  use Ecto.Migration

  def up do
    drop_if_exists constraint(:account_audit_events, :account_audit_events_event_must_be_valid)

    create constraint(:account_audit_events, :account_audit_events_event_must_be_valid,
             check: """
             event IN (
               'login_succeeded', 'login_failed', 'logout', 'registered',
               'email_confirmed', 'email_changed', 'password_changed',
               'password_reset', 'profile_updated', 'role_changed',
               'active_mode_changed'
             )
             """
           )
  end

  def down do
    drop_if_exists constraint(:account_audit_events, :account_audit_events_event_must_be_valid)

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
