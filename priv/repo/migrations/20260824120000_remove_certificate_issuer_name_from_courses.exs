defmodule Wasomi.Repo.Migrations.RemoveCertificateIssuerNameFromCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      remove :certificate_issuer_name, :string
    end
  end
end
