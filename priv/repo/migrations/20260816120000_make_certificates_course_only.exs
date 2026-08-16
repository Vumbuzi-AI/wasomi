defmodule Wasomi.Repo.Migrations.MakeCertificatesCourseOnly do
  use Ecto.Migration

  def up do
    execute("DELETE FROM certificates WHERE type = 'module'")

    drop constraint(:certificates, :certificates_scope_must_match_type)
    drop constraint(:certificates, :certificates_type_must_be_valid)

    drop_if_exists unique_index(:certificates, [:user_id, :module_id],
                     name: :certificates_unique_module_scope
                   )

    drop_if_exists unique_index(:certificates, [:user_id, :course_id],
                     name: :certificates_unique_course_scope
                   )

    alter table(:certificates) do
      remove :module_id
    end

    create constraint(:certificates, :certificates_type_must_be_course, check: "type = 'course'")

    create unique_index(:certificates, [:user_id, :course_id],
             name: :certificates_unique_course_scope
           )
  end

  def down do
    drop constraint(:certificates, :certificates_type_must_be_course)

    drop_if_exists unique_index(:certificates, [:user_id, :course_id],
                     name: :certificates_unique_course_scope
                   )

    alter table(:certificates) do
      add :module_id, references(:modules, on_delete: :delete_all)
    end

    create constraint(:certificates, :certificates_type_must_be_valid,
             check: "type IN ('module', 'course')"
           )

    create constraint(:certificates, :certificates_scope_must_match_type,
             check:
               "(type = 'module' AND module_id IS NOT NULL) OR " <>
                 "(type = 'course' AND module_id IS NULL)"
           )

    create unique_index(:certificates, [:user_id, :module_id],
             where: "type = 'module'",
             name: :certificates_unique_module_scope
           )

    create unique_index(:certificates, [:user_id, :course_id],
             where: "type = 'course'",
             name: :certificates_unique_course_scope
           )
  end
end
