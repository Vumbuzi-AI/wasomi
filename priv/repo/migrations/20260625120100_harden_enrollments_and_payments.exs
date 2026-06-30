defmodule Wasomi.Repo.Migrations.HardenEnrollmentsAndPayments do
  use Ecto.Migration

  def change do
    alter table(:enrollments) do
      modify :status, :string, null: false, default: "pending"
      modify :enrolled_at, :utc_datetime, null: false
      modify :activated_at, :utc_datetime, null: true

      modify :user_id, references(:users, on_delete: :delete_all),
        null: false,
        from: references(:users, on_delete: :nothing)

      modify :course_id, references(:courses, on_delete: :delete_all),
        null: false,
        from: references(:courses, on_delete: :nothing)
    end

    create constraint(:enrollments, :enrollments_status_must_be_valid,
             check: "status IN ('pending', 'active')"
           )

    create constraint(:enrollments, :enrollments_activation_must_match_status,
             check:
               "(status = 'pending' AND activated_at IS NULL) OR (status = 'active' AND activated_at IS NOT NULL)"
           )

    alter table(:payments) do
      modify :provider, :string, null: false
      modify :provider_reference, :string, null: false
      modify :amount_minor, :integer, null: false
      modify :currency, :string, null: false
      modify :status, :string, null: false, default: "pending"
      modify :raw_payload, :map, null: false, default: %{}
      modify :paid_at, :utc_datetime, null: true

      modify :user_id, references(:users, on_delete: :delete_all),
        null: false,
        from: references(:users, on_delete: :nothing)

      modify :course_id, references(:courses, on_delete: :delete_all),
        null: false,
        from: references(:courses, on_delete: :nothing)

      modify :enrollment_id, references(:enrollments, on_delete: :delete_all),
        null: false,
        from: references(:enrollments, on_delete: :nothing)
    end

    create constraint(:payments, :payments_provider_must_be_valid,
             check: "provider IN ('mpesa', 'paystack')"
           )

    create constraint(:payments, :payments_status_must_be_valid,
             check: "status IN ('pending', 'successful', 'failed')"
           )

    create constraint(:payments, :payments_amount_must_be_positive, check: "amount_minor > 0")

    create constraint(:payments, :payments_paid_at_must_match_status,
             check:
               "(status = 'successful' AND paid_at IS NOT NULL) OR (status <> 'successful' AND paid_at IS NULL)"
           )

    create index(:payments, [:provider, :status, :inserted_at])
  end
end
