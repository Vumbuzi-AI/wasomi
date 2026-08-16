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

    course_id =
      Map.get_lazy(attrs, :course_id, fn -> Wasomi.CatalogFixtures.course_fixture().id end)

    {:ok, certificate} =
      attrs
      |> Map.put(:user_id, user_id)
      |> Map.put(:course_id, course_id)
      |> Enum.into(%{
        file_key: "some file_key",
        issued_at: ~U[2026-06-24 10:02:00Z],
        serial_number: unique_certificate_serial_number(),
        type: :course
      })
      |> Wasomi.Certificates.create_certificate()

    certificate
  end
end
