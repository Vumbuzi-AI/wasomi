defmodule Wasomi.CertificatesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Wasomi.Certificates` context.
  """

  @doc """
  Generate a unique certificate serial_number.
  """
  def unique_certificate_serial_number,
    do: "some serial_number#{System.unique_integer([:positive])}"

  @doc """
  Generate a certificate.
  """
  def certificate_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    user_id = Map.get_lazy(attrs, :user_id, fn -> Wasomi.AccountsFixtures.user_fixture().id end)
    type = Map.get(attrs, :type, :module)

    {course_id, module_id} =
      case type do
        :course ->
          {Map.get_lazy(attrs, :course_id, fn -> Wasomi.CatalogFixtures.course_fixture().id end),
           nil}

        :module ->
          module =
            case Map.get(attrs, :module_id) do
              nil -> Wasomi.CatalogFixtures.course_module_fixture()
              module_id -> Wasomi.Catalog.get_course_module!(module_id)
            end

          {Map.get(attrs, :course_id, module.course_id), module.id}
      end

    {:ok, certificate} =
      attrs
      |> Map.put(:user_id, user_id)
      |> Map.put(:course_id, course_id)
      |> Map.put(:module_id, module_id)
      |> Enum.into(%{
        file_key: "some file_key",
        issued_at: ~U[2026-06-24 10:02:00Z],
        serial_number: unique_certificate_serial_number(),
        type: :module
      })
      |> Wasomi.Certificates.create_certificate()

    certificate
  end
end
