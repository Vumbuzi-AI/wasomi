defmodule Wasomi.Repo.Migrations.RemoveModuleCertificates do
  @moduledoc """
  Module completion no longer issues its own certificate (only course
  completion does — see `Wasomi.Certificates.enqueue_for_completion_events/2`).
  This finishes that by removing `:module`-type certificates from the schema
  entirely, rather than leaving dead, unreachable support for them around.

  Deliberately destructive, per an explicit decision: any already-issued
  module certificates are deleted outright (their storage objects are left
  as orphaned files in R2 — there's no delete callback wired up for
  certificate storage, and they're unreachable once their DB row and GDTI
  stop resolving, so it isn't worth adding one just for this one-time
  cleanup).
  """

  use Ecto.Migration

  def up do
    execute "DELETE FROM certificates WHERE type = 'module'"

    drop constraint(:certificates, :certificates_scope_must_match_type)
    drop constraint(:certificates, :certificates_type_must_be_valid)
    drop index(:certificates, [:user_id, :module_id], name: :certificates_unique_module_scope)
    drop index(:certificates, [:module_id])

    alter table(:certificates) do
      remove :module_id
    end

    create constraint(:certificates, :certificates_type_must_be_valid, check: "type = 'course'")
  end

  def down do
    alter table(:certificates) do
      add :module_id, references(:modules, on_delete: :nothing)
    end

    drop constraint(:certificates, :certificates_type_must_be_valid)

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

    create index(:certificates, [:module_id])
  end
end
