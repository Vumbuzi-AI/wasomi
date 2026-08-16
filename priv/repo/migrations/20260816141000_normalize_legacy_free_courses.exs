defmodule Wasomi.Repo.Migrations.NormalizeLegacyFreeCourses do
  use Ecto.Migration

  def up do
    # Free courses use an explicit flag and have no price. Older records used
    # either NULL or zero to represent the same state.
    alter table(:courses) do
      modify :price_minor, :integer, null: true
    end

    execute("""
    UPDATE courses
    SET is_free = TRUE, price_minor = NULL
    WHERE price_minor IS NULL OR price_minor = 0
    """)
  end

  def down do
    execute("""
    UPDATE courses
    SET price_minor = 0
    WHERE is_free = TRUE AND price_minor IS NULL
    """)
  end
end
