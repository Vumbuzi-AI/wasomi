defmodule Wasomi.Repo.Migrations.AddSecondCertificateSignatoryToCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :certificate_signatory_two_name, :string
      add :certificate_signatory_two_title, :string
      add :certificate_signatory_two_signature_key, :string
    end
  end
end
