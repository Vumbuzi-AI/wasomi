defmodule Wasomi.Repo.Migrations.CreateAdminInvitations do
  use Ecto.Migration

  def change do
    create table(:admin_invitations) do
      add :email, :string, null: false
      add :token, :binary, null: false
      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime
      add :revoked_at, :utc_datetime
      add :invited_by_id, references(:users, on_delete: :nilify_all)
      add :accepted_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:admin_invitations, [:token])
    create index(:admin_invitations, [:email])
    create index(:admin_invitations, [:invited_by_id])

    # At most one live invite per email; accepted/revoked rows don't block a re-invite.
    create unique_index(:admin_invitations, [:email],
             where: "status = 'pending'",
             name: :admin_invitations_one_pending_per_email
           )

    create constraint(:admin_invitations, :admin_invitations_status_must_be_valid,
             check: "status IN ('pending', 'accepted', 'revoked')"
           )
  end
end
