defmodule Wasomi.Repo.Migrations.RelaxUsersPhoneToE164 do
  use Ecto.Migration

  # `users.phone` was locked to the Kenyan M-Pesa MSISDN shape
  # (`^2547[0-9]{8}$`). Registration now collects an optional international
  # number, stored E.164 (`+<country><subscriber>`, max 15 digits).
  # `payments.phone` keeps its own Kenyan constraint — M-Pesa STK push still
  # needs `2547XXXXXXXX`.
  def up do
    drop constraint(:users, :users_phone_must_be_normalized)

    execute("""
    UPDATE users SET phone = '+' || phone WHERE phone ~ '^2547[0-9]{8}$'
    """)

    create constraint(:users, :users_phone_must_be_e164,
             check: "phone IS NULL OR phone ~ '^\\+[1-9][0-9]{6,14}$'"
           )
  end

  def down do
    drop constraint(:users, :users_phone_must_be_e164)

    # Restore the Kenyan-only shape: strip the `+` from `+2547XXXXXXXX`, and
    # drop anything the old constraint could not hold.
    execute("""
    UPDATE users SET phone = substring(phone from 2) WHERE phone ~ '^\\+2547[0-9]{8}$'
    """)

    execute("""
    UPDATE users SET phone = NULL WHERE phone IS NOT NULL AND phone !~ '^2547[0-9]{8}$'
    """)

    create constraint(:users, :users_phone_must_be_normalized, check: "phone ~ '^2547[0-9]{8}$'")
  end
end
