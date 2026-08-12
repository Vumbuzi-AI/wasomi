defmodule WasomiWeb.AdminLive.PaymentsTest do
  use WasomiWeb.ConnCase

  import Mox
  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.PaymentsFixtures

  alias Wasomi.{Enrollments, Payments}

  setup :verify_on_exit!

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  defp success_payload(payment) do
    %{
      "id" => 123,
      "reference" => payment.provider_reference,
      "status" => "success",
      "amount" => payment.amount_minor,
      "currency" => payment.currency,
      "paid_at" => "2026-06-25T12:00:00Z",
      "gateway_response" => "Approved"
    }
  end

  test "shows Reconcile only for pending payments", %{conn: conn} do
    pending = payment_fixture(status: :pending)
    successful = payment_fixture(status: :successful)

    {:ok, view, _html} = live(conn, ~p"/admin/payments")

    assert has_element?(
             view,
             ~s{button[phx-value-id="#{pending.id}"]},
             "Reconcile"
           )

    refute has_element?(view, ~s{button[phx-value-id="#{successful.id}"]})
  end

  test "reconciling a pending payment against a live provider success activates the enrollment",
       %{conn: conn} do
    payment = payment_fixture(status: :pending)
    enrollment = Wasomi.Enrollments.get_enrollment!(payment.enrollment_id)

    expect(Wasomi.Payments.ProviderMock, :verify, fn reference ->
      assert reference == payment.provider_reference
      {:ok, success_payload(payment)}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/payments")

    html =
      view
      |> element(~s{button[phx-value-id="#{payment.id}"]}, "Reconcile")
      |> render_click()

    assert html =~ "Payment verified as successful"
    assert html =~ "Approved"
    refute has_element?(view, ~s{button[phx-value-id="#{payment.id}"]})

    assert Payments.get_payment!(payment.id).status == :successful
    assert Enrollments.get_enrollment!(enrollment.id).status == :active
  end

  test "reconciling against a provider decline surfaces the reason and keeps access revoked",
       %{conn: conn} do
    payment = payment_fixture(status: :pending)

    expect(Wasomi.Payments.ProviderMock, :verify, fn _reference ->
      {:ok,
       success_payload(payment)
       |> Map.put("status", "failed")
       |> Map.put("gateway_response", "Insufficient Funds")}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/payments")

    html =
      view
      |> element(~s{button[phx-value-id="#{payment.id}"]}, "Reconcile")
      |> render_click()

    assert html =~ "not successful"
    assert html =~ "Insufficient Funds"
    assert Payments.get_payment!(payment.id).status == :failed
  end

  test "reconciling with a malformed payment id does not crash the view", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/payments")

    html = render_click(view, "reconcile", %{"id" => "not-a-number"})

    assert html =~ "Invalid payment id"
    assert Process.alive?(view.pid)
  end

  test "reconciling tolerates surrounding whitespace in the payment id", %{conn: conn} do
    payment = payment_fixture(status: :pending)

    expect(Wasomi.Payments.ProviderMock, :verify, fn _reference ->
      {:ok, success_payload(payment)}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/payments")

    html = render_click(view, "reconcile", %{"id" => " #{payment.id} \n"})

    assert html =~ "Payment verified as successful"
  end

  test "reconciling a numeric id for a payment that no longer exists does not crash the view",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/payments")

    html = render_click(view, "reconcile", %{"id" => "999999999"})

    assert html =~ "no longer exists"
    assert Process.alive?(view.pid)
  end

  test "searches payments by learner name", %{conn: conn} do
    match_user = user_fixture(name: "Amina Otieno")
    other_user = user_fixture(name: "Brian Kamau")
    match = payment_fixture(user_id: match_user.id, status: :successful)
    other = payment_fixture(user_id: other_user.id, status: :successful)

    {:ok, view, _html} = live(conn, ~p"/admin/payments")

    html =
      view
      |> form("form[phx-change=search]", %{"q" => "Amina"})
      |> render_change()

    assert html =~ match.provider_reference
    refute html =~ other.provider_reference
  end

  test "filters payments by status via the status pills", %{conn: conn} do
    pending = payment_fixture(status: :pending)
    successful = payment_fixture(status: :successful)

    {:ok, view, _html} = live(conn, ~p"/admin/payments")

    html =
      view
      |> element(~s(a[href="/admin/payments?status=successful"]))
      |> render_click()

    assert html =~ successful.provider_reference
    refute html =~ pending.provider_reference
  end

  test "paginates payment transactions, 10 per page", %{conn: conn} do
    Enum.each(1..11, fn _ -> payment_fixture(status: :successful) end)

    {:ok, view, html} = live(conn, ~p"/admin/payments")

    assert html =~ "11 records"
    assert html =~ "Page 1 of 2"
    refute html =~ "Previous"
    assert html =~ "Next"

    html =
      view
      |> element(~s(a[href="/admin/payments?page=2"]))
      |> render_click()

    assert html =~ "Page 2 of 2"
  end

  test "shows a no-matches message on the payments tab", %{conn: conn} do
    payment_fixture(status: :successful)

    {:ok, view, _html} = live(conn, ~p"/admin/payments")

    html =
      view
      |> form("form[phx-change=search]", %{"q" => "nonexistent learner"})
      |> render_change()

    assert html =~ "No payments match the current search or status filter."
  end

  describe "revenue tab" do
    test "shows gross revenue, paid enrolments, and per-course rows", %{conn: conn} do
      course = course_fixture(title: "Applied Negotiation")

      payment_fixture(
        course_id: course.id,
        status: :successful,
        amount_minor: 5_000,
        paid_at: ~U[2026-06-20 10:00:00Z]
      )

      payment_fixture(course_id: course.id, status: :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/payments")

      html = view |> element("a", "Revenue") |> render_click()

      assert html =~ "Applied Negotiation"
      assert html =~ Payments.format_minor(5_000)
      assert_patched(view, ~p"/admin/payments?tab=revenue")
    end

    test "searches courses by title", %{conn: conn} do
      match = course_fixture(title: "Applied Negotiation")
      other = course_fixture(title: "Data Analysis")
      payment_fixture(course_id: match.id, status: :successful)
      payment_fixture(course_id: other.id, status: :successful)

      {:ok, view, _html} = live(conn, ~p"/admin/payments?tab=revenue")

      html =
        view
        |> form("form[phx-change=search]", %{"q" => "Applied"})
        |> render_change()

      assert html =~ match.title
      refute html =~ other.title
    end
  end

  describe "sorting" do
    test "clicking a column header sorts ascending, then descending on a second click", %{
      conn: conn
    } do
      small = payment_fixture(amount_minor: 1_000)
      big = payment_fixture(amount_minor: 9_000)

      {:ok, view, _html} = live(conn, ~p"/admin/payments")

      html = view |> element("th a", "Amount") |> render_click()
      assert_patched(view, ~p"/admin/payments?sort_by=amount&sort_dir=asc")

      [first_pos, second_pos] =
        positions(html, [small.provider_reference, big.provider_reference])

      assert first_pos < second_pos

      html = view |> element("th a", "Amount") |> render_click()
      assert_patched(view, ~p"/admin/payments?sort_by=amount")

      [first_pos, second_pos] =
        positions(html, [big.provider_reference, small.provider_reference])

      assert first_pos < second_pos
    end

    test "sorting preserves the current search and status filter", %{conn: conn} do
      course = course_fixture(title: "Applied Negotiation")
      payment_fixture(course_id: course.id, status: :successful)

      {:ok, view, _html} =
        live(conn, ~p"/admin/payments?status=successful&q=#{course.title}")

      view |> element("th a", "Date") |> render_click()

      assert_patched(
        view,
        ~p"/admin/payments?status=successful&q=#{course.title}&sort_dir=asc"
      )
    end
  end

  defp positions(html, needles) do
    Enum.map(needles, fn needle ->
      {pos, _len} = :binary.match(html, needle)
      pos
    end)
  end
end
