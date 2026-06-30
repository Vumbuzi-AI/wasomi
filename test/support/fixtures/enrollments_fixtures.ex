defmodule Wasomi.EnrollmentsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Wasomi.Enrollments` context.
  """

  @doc """
  Generate a enrollment.
  """
  def enrollment_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    user_id = Map.get_lazy(attrs, :user_id, fn -> Wasomi.AccountsFixtures.user_fixture().id end)

    course_id =
      Map.get_lazy(attrs, :course_id, fn -> Wasomi.CatalogFixtures.course_fixture().id end)

    status = Map.get(attrs, :status, :pending)

    {:ok, enrollment} =
      attrs
      |> Map.put(:user_id, user_id)
      |> Map.put(:course_id, course_id)
      |> Map.put_new(
        :activated_at,
        if(status == :active, do: ~U[2026-06-24 10:02:00Z], else: nil)
      )
      |> Enum.into(%{
        enrolled_at: ~U[2026-06-24 10:02:00Z],
        status: status
      })
      |> Wasomi.Enrollments.create_enrollment()

    enrollment
  end
end
