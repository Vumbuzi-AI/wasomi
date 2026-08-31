defmodule Wasomi.Repo.Migrations.AddGenderToUsers do
  use Ecto.Migration

  # Optional self-reported gender, collected during onboarding (`/welcome`) and
  # editable from account settings. Constrained to a fixed set; NULL means
  # "not provided".
  def change do
    alter table(:users) do
      add :gender, :string
    end

    create constraint(:users, :users_gender_must_be_valid,
             check: "gender IS NULL OR gender IN ('female', 'male', 'prefer_not_to_say')"
           )
  end
end
