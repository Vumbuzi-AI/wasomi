defmodule Wasomi.Accounts.AdminInvitation do
  @moduledoc """
  An invitation for someone to become a Wasomi admin.

  The raw token is only ever in the emailed accept link; the row stores its
  SHA-256 hash. An invitation is `:pending` until it is `:accepted` or
  `:revoked`; a pending row past `expires_at` is treated as expired (see
  `Wasomi.Accounts.admin_invitation_state/1`) but keeps its `:pending` status
  so it can still be resent.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Wasomi.Accounts.User

  @hash_algorithm :sha256
  @rand_size 32
  @validity_days 7

  schema "admin_invitations" do
    field :email, :string
    field :token, :binary, redact: true
    field :status, Ecto.Enum, values: [:pending, :accepted, :revoked], default: :pending
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :invited_by, User
    belongs_to :accepted_by, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a pending invitation for `email` from `invited_by`, returning the
  changeset and the raw (unhashed) token to put in the accept link.
  """
  def build(email, invited_by) do
    {raw_token, hashed_token} = new_token()

    changeset =
      %__MODULE__{}
      |> cast(%{email: email}, [:email])
      |> validate_required([:email])
      |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
      |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
      |> validate_length(:email, max: 160)
      |> put_change(:token, hashed_token)
      |> put_change(:status, :pending)
      |> put_change(:expires_at, expiry())
      |> put_change(:invited_by_id, invited_by.id)
      |> unique_constraint(:email, name: :admin_invitations_one_pending_per_email)

    {changeset, raw_token}
  end

  @doc "Rotates the token and pushes the expiry out (for resend). Returns `{changeset, raw_token}`."
  def refresh(%__MODULE__{} = invitation) do
    {raw_token, hashed_token} = new_token()

    changeset =
      invitation
      |> change(token: hashed_token, expires_at: expiry())

    {changeset, raw_token}
  end

  def revoke_changeset(%__MODULE__{} = invitation) do
    change(invitation, status: :revoked, revoked_at: now())
  end

  def accept_changeset(%__MODULE__{} = invitation, %User{} = accepted_by) do
    change(invitation,
      status: :accepted,
      accepted_at: now(),
      accepted_by_id: accepted_by.id
    )
  end

  @doc "A changeset for the admin invite form — email presence and shape only."
  def invite_form_changeset(attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
  end

  @doc "SHA-256 of the raw token, for looking a row up by an emailed token."
  def hash_token(raw_token), do: :crypto.hash(@hash_algorithm, raw_token)

  defp new_token do
    raw = Base.url_encode64(:crypto.strong_rand_bytes(@rand_size), padding: false)
    {raw, hash_token(raw)}
  end

  defp expiry,
    do: DateTime.utc_now() |> DateTime.add(@validity_days, :day) |> DateTime.truncate(:second)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
