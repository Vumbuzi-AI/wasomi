defmodule Wasomi.Repo.Migrations.MovePhoneToPayments do
  use Ecto.Migration

  def change do
    # Phone is no longer collected at registration; it is captured per-payment
    # so learners can choose the number that receives the M-Pesa prompt.
    alter table(:users) do
      modify :phone, :string, null: true, from: {:string, null: false}
    end

    alter table(:payments) do
      add :phone, :string
    end

    create constraint(:payments, :payments_phone_must_be_normalized,
             check: "phone IS NULL OR phone ~ '^2547[0-9]{8}$'"
           )
  end
end
