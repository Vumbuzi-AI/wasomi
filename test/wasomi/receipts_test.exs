defmodule Wasomi.ReceiptsTest do
  use Wasomi.DataCase, async: true

  import Mox
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.PaymentsFixtures

  alias Wasomi.Payments.Payment
  alias Wasomi.Receipts
  alias Wasomi.Receipts.Template

  setup :verify_on_exit!

  defp paid(user, attrs \\ %{}) do
    course = course_fixture(status: :published)

    payment_fixture(
      Map.merge(
        %{user_id: user.id, course_id: course.id, status: :successful},
        Map.new(attrs)
      )
    )
  end

  describe "list_for_user/1" do
    test "returns only the user's successful payments, newest first" do
      user = user_fixture()
      other = user_fixture()

      _a = paid(user, %{provider_reference: "R-A"})
      _b = paid(user, %{provider_reference: "R-B"})
      _theirs = paid(other, %{provider_reference: "R-OTHER"})

      refs = Receipts.list_for_user(user) |> Enum.map(& &1.provider_reference)
      assert "R-A" in refs and "R-B" in refs
      refute "R-OTHER" in refs
    end
  end

  describe "page_for_user/2" do
    test "returns a paginated page of the user's receipts" do
      user = user_fixture()
      for n <- 1..7, do: paid(user, %{provider_reference: "P-#{n}"})

      page1 = Receipts.page_for_user(user, page: 1, page_size: 5)
      assert page1.total_count == 7
      assert page1.total_pages == 2
      assert length(page1.entries) == 5
      assert Enum.all?(page1.entries, &match?(%{course: %{title: _}}, &1))

      page2 = Receipts.page_for_user(user, page: 2, page_size: 5)
      assert length(page2.entries) == 2
    end
  end

  describe "get_for_user/2" do
    test "returns the learner's own successful payment with the course preloaded" do
      user = user_fixture()
      payment = paid(user)

      assert %{id: id, course: %{title: _}} = Receipts.get_for_user(user, payment.id)
      assert id == payment.id
    end

    test "is nil for someone else's payment, a pending one, or a bad id" do
      user = user_fixture()
      stranger = user_fixture()

      theirs = paid(stranger)
      pending = paid(user, %{status: :pending, provider_reference: "R-PENDING"})

      assert Receipts.get_for_user(user, theirs.id) == nil
      assert Receipts.get_for_user(user, pending.id) == nil
      assert Receipts.get_for_user(user, "not-an-id") == nil
      assert Receipts.get_for_user(user, 0) == nil
    end
  end

  describe "pdf_for/2" do
    test "renders the receipt through the configured renderer with billing assigns" do
      user = user_fixture(%{name: "Ada Lovelace"})
      course = course_fixture(status: :published, title: "GS1 Foundations")

      payment =
        payment_fixture(%{
          user_id: user.id,
          course_id: course.id,
          status: :successful,
          amount_minor: 4500,
          currency: "KES",
          provider: :paystack,
          provider_reference: "PS-123"
        })

      expect(Wasomi.ReceiptRendererMock, :render, fn assigns ->
        assert assigns.billed_to_name == "Ada Lovelace"
        assert assigns.course_title == "GS1 Foundations"
        assert assigns.reference == "PS-123"
        assert assigns.payment_method == "Paystack"
        assert assigns.amount =~ "KES"
        assert assigns.receipt_no == "WSM-" <> String.pad_leading(to_string(payment.id), 5, "0")
        assert assigns.issued_on =~ ~r/\d{4} · \d{1,2}:\d{2} (AM|PM) UTC$/
        {:ok, "%PDF-1.4 fake"}
      end)

      assert {:ok, "%PDF-1.4 fake"} = Receipts.pdf_for(user, payment.id)
    end

    test "is {:error, :not_found} when the payment isn't the user's receipt" do
      user = user_fixture()
      stranger = user_fixture()
      payment = paid(stranger)

      assert Receipts.pdf_for(user, payment.id) == {:error, :not_found}
    end
  end

  test "filename/1 is derived from the provider reference" do
    assert Receipts.filename(%Payment{provider_reference: "PS_abc 123"}) ==
             "wasomi-receipt-PS-abc-123.pdf"
  end

  test "the template embeds the Outfit @font-face and the receipt content" do
    html =
      Template.render_html(%{
        issuer_name: "GS1 Kenya",
        address_lines: ["Nairobi, Kenya"],
        issuer_email: "info@gs1kenya.org",
        issuer_website: "www.gs1kenya.org",
        receipt_no: "WSM-00007",
        reference: "PS-XYZ",
        issued_on: "August 14, 2026 · 10:00 AM UTC",
        billed_to_name: "One Student",
        billed_to_email: "student@example.com",
        course_title: "The Human Stack",
        amount: "15,000 KES",
        tax: "0 KES",
        payment_method: "Paystack"
      })

    assert html =~ "@font-face"
    assert html =~ ~s(font-family: "Outfit")
    assert html =~ "Order summary"
    assert html =~ "Total paid"
    assert html =~ "WSM-00007"
    assert html =~ "15,000 KES"
    assert html =~ "PS-XYZ"
  end
end
