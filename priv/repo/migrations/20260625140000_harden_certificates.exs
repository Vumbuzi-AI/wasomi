defmodule Wasomi.Repo.Migrations.HardenCertificates do
  use Ecto.Migration

  def change do
    alter table(:certificates) do
      modify :type, :string, null: false
      modify :serial_number, :string, null: false
      modify :file_key, :string, null: false
      modify :issued_at, :utc_datetime, null: false
      modify :user_id, :bigint, null: false
      modify :course_id, :bigint, null: false
      modify :module_id, :bigint
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
