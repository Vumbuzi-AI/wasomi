defmodule Wasomi.Accounts.AuditEvent do
  @moduledoc """
  Append-only account/security audit event.

  Metadata is intentionally small and sanitized by the Accounts context before
  insert. Keep request provenance (`ip_address`, `user_agent`) in dedicated
  columns so callers do not need to duplicate that shape in arbitrary metadata.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Wasomi.Accounts.User

  @event_values [
    :login_succeeded,
    :login_failed,
    :logout,
    :registered,
    :email_confirmed,
    :email_changed,
    :password_changed,
    :password_reset,
    :profile_updated,
    :role_changed
  ]

  schema "account_audit_events" do
    field :event, Ecto.Enum, values: @event_values
    field :metadata, :map, default: %{}
    field :ip_address, :string
    field :user_agent, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Known event values accepted by the audit-event changeset."
  def event_values, do: @event_values

  def changeset(audit_event, attrs) do
    audit_event
    |> cast(attrs, [:event, :metadata, :ip_address, :user_agent, :user_id])
    |> validate_required([:event, :metadata])
    |> validate_length(:ip_address, max: 128)
    |> validate_length(:user_agent, max: 512)
    |> foreign_key_constraint(:user_id)
  end
end
