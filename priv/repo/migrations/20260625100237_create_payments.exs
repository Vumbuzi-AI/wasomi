defmodule Wasomi.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    create table(:payments) do
      add :provider, :string
      add :provider_reference, :string
      add :amount_minor, :integer
      add :currency, :string
      add :status, :string
      add :raw_payload, :map
      add :paid_at, :utc_datetime
      add :user_id, references(:users, on_delete: :nothing)
      add :course_id, references(:courses, on_delete: :nothing)
      add :enrollment_id, references(:enrollments, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:payments, [:provider_reference])
    create index(:payments, [:user_id])
    create index(:payments, [:course_id])
    create index(:payments, [:enrollment_id])
  end
end
