defmodule Wasomi.Repo.Migrations.AddResourceScopeToStudyGuides do
  use Ecto.Migration

  def change do
    # A third scope alongside module and lecture: one specific PDF. A lecture can
    # carry several readings, and "explain this one document to me" is a different
    # ask from "explain this whole lesson" — so each resource can now carry its
    # own guides, and the exclusivity constraint widens from a two-way XOR to
    # "exactly one of the three".
    alter table(:study_guides) do
      add :lecture_resource_id, references(:lecture_resources, on_delete: :delete_all)
    end

    create index(:study_guides, [:user_id, :lecture_resource_id])

    drop constraint(:study_guides, :study_guides_scope_must_be_exclusive)

    create constraint(:study_guides, :study_guides_scope_must_be_exclusive,
             check: """
             (CASE WHEN module_id IS NOT NULL THEN 1 ELSE 0 END) +
             (CASE WHEN lecture_id IS NOT NULL THEN 1 ELSE 0 END) +
             (CASE WHEN lecture_resource_id IS NOT NULL THEN 1 ELSE 0 END) = 1
             """
           )
  end
end

