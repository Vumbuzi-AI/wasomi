defmodule Wasomi.Repo.Migrations.SplitUserNameIntoFirstLast do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :first_name, :string
      add :last_name, :string
    end

    # Best-effort backfill: first whitespace-delimited token is the first
    # name, the remainder is the last name. `name` stays as the canonical
    # display/certificate string.
    execute(
      """
      UPDATE users
      SET first_name = split_part(name, ' ', 1),
          last_name  = NULLIF(btrim(substr(name, length(split_part(name, ' ', 1)) + 2)), '')
      WHERE first_name IS NULL
      """,
      ""
    )
  end
end
