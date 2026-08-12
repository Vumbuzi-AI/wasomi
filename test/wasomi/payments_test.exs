defmodule Wasomi.PaymentsTest do
  use Wasomi.DataCase
  use Oban.Testing, repo: Wasomi.Repo

  import Mox
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.PaymentsFixtures

  alias Wasomi.{Enrollments, Payments, Repo}
  alias Wasomi.Payments.Workers.{ProcessPaystackWebhook, ReconcilePendingPayments}

  setup :verify_on_exit!

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

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

  describe "verify_transaction/2" do
    setup do
      %{admin: admin_fixture()}
    end

    test "rejects a non-admin caller without querying the provider", %{admin: _admin} do
      user = user_fixture()
      course = course_fixture(price_minor: 80_000, currency: "KES")
      {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)

      assert {:error, :forbidden} = Payments.verify_transaction(payment.id, user)
    end

    test "rejects a nil or non-User caller without raising" do
      assert {:error, :forbidden} = Payments.verify_transaction(1, nil)
      assert {:error, :forbidden} = Payments.verify_transaction(1, "not-a-user")
    end

    test "returns an error tuple instead of raising for a nonexistent payment id", %{
      admin: admin
    } do
      assert {:error, :payment_not_found} = Payments.verify_transaction(-1, admin)
    end

    test "provider success atomically completes payment and activates enrollment", %{
      admin: admin
    } do
      user = user_fixture()
      course = course_fixture(price_minor: 80_000, currency: "KES")
      {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)
      Payments.subscribe(user)

      expect(Wasomi.Payments.ProviderMock, :verify, fn reference ->
        assert reference == payment.provider_reference
        {:ok, success_payload(payment)}
      end)

      assert {:ok, %{payment: successful, enrollment: active, verification: verification}} =
               Payments.verify_transaction(payment.id, admin)

      assert successful.status == :successful
      assert active.status == :active
      assert verification["status"] == "success"
      assert Enrollments.can_access_course?(user, course)
      assert_receive {:payment_confirmed, %{id: id}}
      assert id == active.id
    end

    test "provider decline marks the payment failed and returns the provider's reason", %{
      admin: admin
    } do
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
               Payments.verify_transaction(payment.id, admin)

      assert verification["gateway_response"] == "Insufficient Funds"
      assert Payments.get_payment!(payment.id).status == :failed
      assert Repo.reload(enrollment).status == :pending
      refute Enrollments.can_access_course?(user, course)
    end

    test "amount mismatch is rejected without granting access", %{admin: admin} do
      user = user_fixture()
      course = course_fixture(price_minor: 80_000, currency: "KES")
      {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)

      expect(Wasomi.Payments.ProviderMock, :verify, fn _reference ->
        {:ok, Map.put(success_payload(payment), "amount", payment.amount_minor + 1)}
      end)

      assert {:error, :amount_mismatch} = Payments.verify_transaction(payment.id, admin)
      refute Enrollments.can_access_course?(user, course)
    end

    test "re-verifying an already failed payment does not call the provider again", %{
      admin: admin
    } do
      user = user_fixture()
      course = course_fixture(price_minor: 80_000, currency: "KES")

      {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)
      {:ok, failed} = Payments.update_payment(payment, %{status: :failed})

      assert {:error, {:already_failed, ^failed}} = Payments.verify_transaction(payment.id, admin)
    end

    test "re-verifying an already successful payment does not call the provider again", %{
      admin: admin
    } do
      user = user_fixture()
      course = course_fixture(price_minor: 80_000, currency: "KES")
      {:ok, %{payment: payment}} = Payments.create_pending_checkout(user, course)

      expect(Wasomi.Payments.ProviderMock, :verify, 1, fn _reference ->
        {:ok, success_payload(payment)}
      end)

      assert {:ok, %{payment: first_payment}} = Payments.verify_transaction(payment.id, admin)
      assert {:ok, %{payment: second_payment}} = Payments.verify_transaction(payment.id, admin)
      assert first_payment.id == second_payment.id
      assert second_payment.status == :successful
    end

    test "a concurrent success wins over a stale decline seen by our own check", %{admin: admin} do
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

      assert {:ok, %{verification: verification}} = Payments.verify_transaction(payment.id, admin)
      assert verification["gateway_response"] == "Confirmed elsewhere"
    end
  end

  describe "list_payments_page/1" do
    test "paginates, newest first, with learner and course preloaded" do
      Enum.each(1..3, fn _ -> payment_fixture() end)

      page = Payments.list_payments_page(page: 1, page_size: 2)

      assert page.total_count == 3
      assert page.total_pages == 2
      assert length(page.entries) == 2
      assert %Wasomi.Accounts.User{} = hd(page.entries).user
      assert %Wasomi.Catalog.Course{} = hd(page.entries).course
    end

    test "filters by status" do
      pending = payment_fixture(status: :pending)
      payment_fixture(status: :successful)

      page = Payments.list_payments_page(status: :pending)

      assert [%{id: id}] = page.entries
      assert id == pending.id
    end

    test "searches by learner name, email, course title, or provider reference" do
      user = user_fixture(name: "Amina Otieno")
      course = course_fixture(title: "Applied Negotiation")
      match = payment_fixture(user_id: user.id, course_id: course.id)
      other = payment_fixture()

      by_name = Payments.list_payments_page(search: "Amina")
      by_course = Payments.list_payments_page(search: "Negotiation")
      by_reference = Payments.list_payments_page(search: match.provider_reference)

      for page <- [by_name, by_course, by_reference] do
        assert [%{id: id}] = page.entries
        assert id == match.id
      end

      refute Enum.any?(by_name.entries, &(&1.id == other.id))
    end

    test "sorts by amount" do
      small = payment_fixture(amount_minor: 1_000)
      big = payment_fixture(amount_minor: 9_000)

      assert [%{id: first}, %{id: second}] =
               Payments.list_payments_page(sort_by: :amount, sort_dir: :asc).entries

      assert first == small.id
      assert second == big.id

      assert [%{id: first_desc}, %{id: second_desc}] =
               Payments.list_payments_page(sort_by: :amount, sort_dir: :desc).entries

      assert first_desc == big.id
      assert second_desc == small.id
    end

    test "sorts by learner name" do
      a = payment_fixture(user_id: user_fixture(name: "Amina").id)
      b = payment_fixture(user_id: user_fixture(name: "Brian").id)

      assert [%{id: first}, %{id: second}] =
               Payments.list_payments_page(sort_by: :learner, sort_dir: :asc).entries

      assert first == a.id
      assert second == b.id
    end

    test "sorts by course title" do
      a = payment_fixture(course_id: course_fixture(title: "Applied Negotiation").id)
      b = payment_fixture(course_id: course_fixture(title: "Basic Excel").id)

      assert [%{id: first}, %{id: second}] =
               Payments.list_payments_page(sort_by: :course, sort_dir: :asc).entries

      assert first == a.id
      assert second == b.id
    end

    test "sorts by provider reference" do
      a = payment_fixture(provider_reference: "AAA-001")
      b = payment_fixture(provider_reference: "ZZZ-999")

      assert [%{id: first}, %{id: second}] =
               Payments.list_payments_page(sort_by: :reference, sort_dir: :asc).entries

      assert first == a.id
      assert second == b.id
    end

    test "sorts by status (alphabetically, since it's stored as a string)" do
      failed = payment_fixture(status: :failed)
      successful = payment_fixture(status: :successful)
      pending = payment_fixture(status: :pending)

      assert Payments.list_payments_page(sort_by: :status, sort_dir: :asc).entries
             |> Enum.map(& &1.id) == [failed.id, pending.id, successful.id]
    end

    test "defaults to date (inserted_at) descending, unaffected by unknown sort_by" do
      first = payment_fixture()
      second = payment_fixture()

      assert [%{id: newest}, %{id: oldest}] =
               Payments.list_payments_page(sort_by: :bogus).entries

      assert newest == second.id
      assert oldest == first.id
    end
  end

  describe "count_successful_by_course/0" do
    test "counts only successful payments, keyed by course" do
      course = course_fixture()
      payment_fixture(course_id: course.id, status: :successful)
      payment_fixture(course_id: course.id, status: :successful)
      payment_fixture(course_id: course.id, status: :pending)

      assert Payments.count_successful_by_course() == %{course.id => 2}
    end
  end

  describe "last_paid_at_by_course/0" do
    test "returns the most recent successful payment's paid_at, keyed by course" do
      course = course_fixture()

      payment_fixture(
        course_id: course.id,
        status: :successful,
        paid_at: ~U[2026-05-01 10:00:00Z]
      )

      payment_fixture(
        course_id: course.id,
        status: :successful,
        paid_at: ~U[2026-06-15 10:00:00Z]
      )

      assert Payments.last_paid_at_by_course() == %{course.id => ~U[2026-06-15 10:00:00Z]}
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
