defmodule Wasomi.Repo.Migrations.CreateCertificates do
  use Ecto.Migration

  def change do
    create table(:certificates) do
      add :type, :string
      add :serial_number, :string
      add :file_key, :string
      add :issued_at, :utc_datetime
      add :user_id, references(:users, on_delete: :nothing)
      add :course_id, references(:courses, on_delete: :nothing)
      add :module_id, references(:modules, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:certificates, [:serial_number])
    create index(:certificates, [:user_id])
    create index(:certificates, [:course_id])
    create index(:certificates, [:module_id])
  end
end
