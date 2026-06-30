defmodule Wasomi.PaymentsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Wasomi.Payments` context.
  """

  @doc """
  Generate a unique payment provider_reference.
  """
  def unique_payment_provider_reference,
    do: "some provider_reference#{System.unique_integer([:positive])}"

  @doc """
  Generate a payment.
  """
  def payment_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    user = Wasomi.AccountsFixtures.user_fixture()
    course = Wasomi.CatalogFixtures.course_fixture(price_minor: 4_200)

    enrollment =
      Wasomi.EnrollmentsFixtures.enrollment_fixture(user_id: user.id, course_id: course.id)

    status = Map.get(attrs, :status, :pending)

    {:ok, payment} =
      attrs
      |> Map.put_new(:user_id, user.id)
      |> Map.put_new(:course_id, course.id)
      |> Map.put_new(:enrollment_id, enrollment.id)
      |> Map.put_new(:paid_at, if(status == :successful, do: ~U[2026-06-24 10:02:00Z]))
      |> Enum.into(%{
        amount_minor: 4_200,
        currency: "KES",
        provider: :paystack,
        provider_reference: unique_payment_provider_reference(),
        raw_payload: %{},
        status: status
      })
      |> Wasomi.Payments.create_payment()

    payment
  end
end
