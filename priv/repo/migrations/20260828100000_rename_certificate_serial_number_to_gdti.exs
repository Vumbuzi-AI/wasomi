defmodule Wasomi.Repo.Migrations.RenameCertificateSerialNumberToGdti do
  use Ecto.Migration

  def change do
    rename table(:certificates), :serial_number, to: :gdti

    drop unique_index(:certificates, [:serial_number])
    create unique_index(:certificates, [:gdti])
  end
end
