defmodule Wasomi.PaymentsTest do
  use Wasomi.DataCase
  use Oban.Testing, repo: Wasomi.Repo

  import Mox
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures

  alias Wasomi.{Enrollments, Payments, Repo}
  alias Wasomi.Payments.Workers.{ProcessPaystackWebhook, ReconcilePendingPayments}

  setup :verify_on_exit!

  test "initialization persists a pending enrollment and payment before calling Paystack" do
    user = user_fixture()
    course = course_fixture(price_minor: 125_000, currency: "KES")

    expect(Wasomi.Payments.ProviderMock, :initiate, fn payment ->
      assert Repo.get!(Wasomi.Payments.Payment, payment.id)
      assert payment.amount_minor == 125_000
      assert payment.provider_reference =~ "KBI-"
      assert payment.user.email == user.email

      {:ok,
       %{
         "authorization_url" => "https://checkout.paystack.test/abc",
         "access_code" => "access-code",
         "reference" => payment.provider_reference,
         "card" => %{"last4" => "4081"}
       }}
    end)

    assert {:ok, result} = Payments.initialize_checkout(user, course)
    assert result.authorization_url == "https://checkout.paystack.test/abc"
    assert result.enrollment.status == :pending
    assert result.payment.status == :pending
    refute Map.has_key?(result.payment.raw_payload["initialization"], "card")
  end

  test "checkout captures and normalises the M-Pesa number for the payment prompt" do
    user = user_fixture()
    course = course_fixture(price_minor: 80_000, currency: "KES")

    {:ok, %{payment: payment}} =
      Payments.create_pending_checkout(user, course, "0712 345-678")

    assert payment.phone == "254712345678"
  end

  test "verified success atomically completes payment and activates enrollment" do
    user = user_fixture()
    course = course_fixture(price_minor: 80_000, currency: "KES")
    {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)
    Payments.subscribe(user)

    expect(Wasomi.Payments.ProviderMock, :verify, fn reference ->
      assert reference == payment.provider_reference
      {:ok, success_payload(payment)}
    end)

    assert {:ok, %{payment: successful, enrollment: active}} =
             Payments.process_paystack_reference(payment.provider_reference)

    assert successful.status == :successful
    assert successful.paid_at
    assert active.status == :active
    assert Enrollments.can_access_course?(user, course)
    assert_receive {:payment_confirmed, %{id: id}}
    assert id == active.id
  end

  test "failed verification does not activate access" do
    user = user_fixture()
    course = course_fixture(price_minor: 80_000, currency: "KES")

    {:ok, %{payment: payment, enrollment: enrollment}} =
      Payments.create_pending_checkout(user, course)

    expect(Wasomi.Payments.ProviderMock, :verify, fn _reference ->
      {:ok, Map.put(success_payload(payment), "status", "failed")}
    end)

    assert {:error, {:payment_failed, failed}} =
             Payments.process_paystack_reference(payment.provider_reference)

    assert failed.status == :failed
    assert Repo.reload(enrollment).status == :pending
    refute Enrollments.can_access_course?(user, course)
  end

  test "duplicate processing is idempotent and does not verify twice" do
    user = user_fixture()
    course = course_fixture(price_minor: 80_000, currency: "KES")
    {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)

    expect(Wasomi.Payments.ProviderMock, :verify, 1, fn _reference ->
      {:ok, success_payload(payment)}
    end)

    assert {:ok, first} = Payments.process_paystack_reference(payment.provider_reference)
    assert {:ok, second} = Payments.process_paystack_reference(payment.provider_reference)
    assert first.payment.id == second.payment.id
    assert first.enrollment.id == second.enrollment.id
  end

  test "amount mismatch is rejected without granting access" do
    user = user_fixture()
    course = course_fixture(price_minor: 80_000, currency: "KES")
    {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)

    expect(Wasomi.Payments.ProviderMock, :verify, fn _reference ->
      {:ok, Map.put(success_payload(payment), "amount", payment.amount_minor + 1)}
    end)

    assert {:error, :amount_mismatch} =
             Payments.process_paystack_reference(payment.provider_reference)

    refute Enrollments.can_access_course?(user, course)
  end

  test "webhook worker verifies before activation and safely handles replay" do
    user = user_fixture()
    course = course_fixture(price_minor: 80_000, currency: "KES")
    {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)

    expect(Wasomi.Payments.ProviderMock, :verify, 1, fn _reference ->
      {:ok, success_payload(payment)}
    end)

    args = %{
      "reference" => payment.provider_reference,
      "event" => %{
        "event" => "charge.success",
        "data" => %{
          "reference" => payment.provider_reference,
          "authorization" => %{"last4" => "4081"}
        }
      }
    }

    assert :ok = ProcessPaystackWebhook.perform(%Oban.Job{args: args})
    assert :ok = ProcessPaystackWebhook.perform(%Oban.Job{args: args})
    assert Enrollments.can_access_course?(user, course)

    stored = Payments.get_payment!(payment.id)
    refute get_in(stored.raw_payload, ["webhook", "data", "authorization"])
  end

  test "stale pending payments are enqueued for reconciliation" do
    user = user_fixture()
    course = course_fixture(price_minor: 80_000, currency: "KES")
    {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)

    Repo.update_all(
      from(p in Wasomi.Payments.Payment, where: p.id == ^payment.id),
      set: [
        inserted_at: DateTime.add(DateTime.utc_now(), -180, :second) |> DateTime.truncate(:second)
      ]
    )

    assert :ok = ReconcilePendingPayments.perform(%Oban.Job{args: %{}})

    assert_enqueued(
      worker: ProcessPaystackWebhook,
      args: %{"reference" => payment.provider_reference}
    )

    expect(Wasomi.Payments.ProviderMock, :verify, fn _reference ->
      {:ok, success_payload(payment)}
    end)

    assert :ok =
             ProcessPaystackWebhook.perform(%Oban.Job{
               args: %{
                 "reference" => payment.provider_reference,
                 "event" => %{"event" => "reconciliation"}
               }
             })

    assert Enrollments.can_access_course?(user, course)
  end

  defp success_payload(payment) do
    %{
      "id" => 123,
      "reference" => payment.provider_reference,
      "status" => "success",
      "amount" => payment.amount_minor,
      "currency" => payment.currency,
      "paid_at" => "2026-06-25T12:00:00Z",
      "authorization" => %{"last4" => "4081"}
    }
  end
end
