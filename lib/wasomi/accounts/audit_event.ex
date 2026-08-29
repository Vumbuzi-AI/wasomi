defmodule Wasomi.Accounts.AuditEvent do
  @moduledoc """
  Append-only account/security audit event.

  Recorded best-effort *after* the account change commits — a failure to
  write the trail is logged and emits telemetry but never rolls back or
  blocks the user's action (see `Wasomi.Accounts.record_account_audit_event/3`).

  Columns: `user_id` is the subject; `actor_id` is who performed the change
  when different (an admin acting on a learner); `ip_address` / `user_agent` /
  `request_id` are request provenance, populated only for events recorded at
  the web layer (login, logout, failed login, email confirmation).

  ## `metadata` shape per event

  `metadata` is a small `jsonb` map, sanitised before insert (secret-bearing
  keys dropped recursively, strings capped, structs filtered). Its shape is
  event-specific — consumers should match defensively:

    * `:registered`, `:email_confirmed`, `:logout`, `:login_succeeded` — `%{}`
    * `:password_changed`, `:password_reset` — `%{}`
    * `:profile_updated` — `%{"changed_fields" => ["bio", "country", ...]}`
    * `:role_changed` — `%{"old_role" => "learner", "new_role" => "admin"}`
    * `:email_changed` — `%{"old_email" => %{"email_fingerprint" => hex, "email_domain" => str},
      "new_email" => %{...}}` (never the raw address)
    * `:login_failed` — `%{"reason" => "invalid_credentials" | "unconfirmed" |
      "captcha_low_score" | "captcha_failed", "email_domain" => str,
      "email_fingerprint" => hex}` (`email_fingerprint` absent if the
      HMAC key isn't configured)
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
    field :request_id, :string

    belongs_to :user, User
    belongs_to :actor, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Known event values accepted by the audit-event changeset."
  def event_values, do: @event_values

  def changeset(audit_event, attrs) do
    audit_event
    |> cast(attrs, [
      :event,
      :metadata,
      :ip_address,
      :user_agent,
      :request_id,
      :user_id,
      :actor_id
    ])
    |> validate_required([:event, :metadata])
    |> validate_length(:ip_address, max: 128)
    |> validate_length(:user_agent, max: 512)
    |> validate_length(:request_id, max: 64)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:actor_id)
  end
end
