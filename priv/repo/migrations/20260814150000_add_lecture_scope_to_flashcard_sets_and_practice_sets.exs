defmodule Wasomi.Repo.Migrations.AddLectureScopeToFlashcardSetsAndPracticeSets do
  use Ecto.Migration

  def change do
    for table_name <- [:flashcard_sets, :practice_sets] do
      alter table(table_name) do
        modify :module_id, :bigint, null: true
        add :lecture_id, references(:lectures, on_delete: :delete_all)
      end

      drop index(table_name, [:module_id])
      create unique_index(table_name, [:module_id], where: "module_id IS NOT NULL")
      create unique_index(table_name, [:lecture_id], where: "lecture_id IS NOT NULL")
    end

    create constraint(:flashcard_sets, :flashcard_sets_scope_must_be_exclusive,
             check: "(module_id IS NOT NULL) <> (lecture_id IS NOT NULL)"
           )

    create constraint(:practice_sets, :practice_sets_scope_must_be_exclusive,
             check: "(module_id IS NOT NULL) <> (lecture_id IS NOT NULL)"
           )
  end
end
