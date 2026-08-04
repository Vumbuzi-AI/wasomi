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

  describe "verify_transaction/1" do
    test "returns an error tuple instead of raising for a nonexistent payment id" do
      assert {:error, :payment_not_found} = Payments.verify_transaction(-1)
    end

    test "provider success atomically completes payment and activates enrollment" do
      user = user_fixture()
      course = course_fixture(price_minor: 80_000, currency: "KES")
      {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)
      Payments.subscribe(user)

      expect(Wasomi.Payments.ProviderMock, :verify, fn reference ->
        assert reference == payment.provider_reference
        {:ok, success_payload(payment)}
      end)

      assert {:ok, %{payment: successful, enrollment: active, verification: verification}} =
               Payments.verify_transaction(payment.id)

      assert successful.status == :successful
      assert active.status == :active
      assert verification["status"] == "success"
      assert Enrollments.can_access_course?(user, course)
      assert_receive {:payment_confirmed, %{id: id}}
      assert id == active.id
    end

    test "provider decline marks the payment failed and returns the provider's reason" do
      user = user_fixture()
      course = course_fixture(price_minor: 80_000, currency: "KES")

      {:ok, %{payment: payment, enrollment: enrollment}} =
        Payments.create_pending_checkout(user, course)

      expect(Wasomi.Payments.ProviderMock, :verify, fn _reference ->
        {:ok,
         success_payload(payment)
         |> Map.put("status", "failed")
         |> Map.put("gateway_response", "Insufficient Funds")}
      end)

      assert {:error, {:provider_declined, verification}} =
               Payments.verify_transaction(payment.id)

      assert verification["gateway_response"] == "Insufficient Funds"
      assert Payments.get_payment!(payment.id).status == :failed
      assert Repo.reload(enrollment).status == :pending
      refute Enrollments.can_access_course?(user, course)
    end

    test "amount mismatch is rejected without granting access" do
      user = user_fixture()
      course = course_fixture(price_minor: 80_000, currency: "KES")
      {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)

      expect(Wasomi.Payments.ProviderMock, :verify, fn _reference ->
        {:ok, Map.put(success_payload(payment), "amount", payment.amount_minor + 1)}
      end)

      assert {:error, :amount_mismatch} = Payments.verify_transaction(payment.id)
      refute Enrollments.can_access_course?(user, course)
    end

    test "re-verifying an already failed payment does not call the provider again" do
      user = user_fixture()
      course = course_fixture(price_minor: 80_000, currency: "KES")

      {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)
      {:ok, failed} = Payments.update_payment(payment, %{status: :failed})

      assert {:error, {:already_failed, ^failed}} = Payments.verify_transaction(payment.id)
    end

    test "re-verifying an already successful payment does not call the provider again" do
      user = user_fixture()
      course = course_fixture(price_minor: 80_000, currency: "KES")
      {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)

      expect(Wasomi.Payments.ProviderMock, :verify, 1, fn _reference ->
        {:ok, success_payload(payment)}
      end)

      assert {:ok, %{payment: first_payment}} = Payments.verify_transaction(payment.id)
      assert {:ok, %{payment: second_payment}} = Payments.verify_transaction(payment.id)
      assert first_payment.id == second_payment.id
      assert second_payment.status == :successful
    end

    test "a concurrent success wins over a stale decline seen by our own check" do
      user = user_fixture()
      course = course_fixture(price_minor: 80_000, currency: "KES")
      {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)

      expect(Wasomi.Payments.ProviderMock, :verify, fn _reference ->
        # Simulate another process (e.g. the webhook) confirming success
        # while our own verification call to the provider is in flight.
        {:ok, _} =
          Payments.update_payment(payment, %{
            status: :successful,
            paid_at: DateTime.utc_now() |> DateTime.truncate(:second),
            raw_payload: %{
              "verification" => %{
                "status" => "success",
                "gateway_response" => "Confirmed elsewhere"
              }
            }
          })

        {:ok,
         success_payload(payment)
         |> Map.put("status", "failed")
         |> Map.put("gateway_response", "Stale decline seen by our own check")}
      end)

      assert {:ok, %{verification: verification}} = Payments.verify_transaction(payment.id)
      assert verification["gateway_response"] == "Confirmed elsewhere"
    end
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
