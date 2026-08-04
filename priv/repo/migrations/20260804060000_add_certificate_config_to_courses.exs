defmodule Wasomi.Repo.Migrations.AddCertificateConfigToCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :certificate_enabled, :boolean, null: false, default: true
      add :certificate_issuer_name, :string
      add :certificate_signatory_name, :string
      add :certificate_signatory_title, :string
      add :certificate_signature_key, :string
    end
  end
end
