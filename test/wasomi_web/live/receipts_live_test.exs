defmodule WasomiWeb.ReceiptsLiveTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Wasomi.{AccountsFixtures, CatalogFixtures, PaymentsFixtures}

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "lists the learner's receipts with a PDF download link", %{conn: conn, user: user} do
    course = course_fixture(status: :published, title: "Traceability 101")

    payment =
      payment_fixture(%{
        user_id: user.id,
        course_id: course.id,
        status: :successful,
        amount_minor: 125_000,
        currency: "KES",
        provider_reference: "RC-PAID"
      })

    {:ok, _lv, html} = live(conn, ~p"/receipts")

    assert html =~ "student-sidebar"
    assert html =~ "Payment receipts"
    assert html =~ "Traceability 101"
    assert html =~ "RC-PAID"
    assert html =~ ~s(href="/receipts/#{payment.id}/download")
  end

  test "hides pending and other learners' payments", %{conn: conn, user: user} do
    course = course_fixture(status: :published)
    stranger = user_fixture()

    _pending =
      payment_fixture(%{
        user_id: user.id,
        course_id: course.id,
        status: :pending,
        provider_reference: "RC-PENDING"
      })

    _theirs =
      payment_fixture(%{
        user_id: stranger.id,
        course_id: course.id,
        status: :successful,
        provider_reference: "RC-STRANGER"
      })

    {:ok, _lv, html} = live(conn, ~p"/receipts")

    refute html =~ "RC-PENDING"
    refute html =~ "RC-STRANGER"
    assert html =~ "No receipts yet."
  end

  test "paginates when there are more than one page of receipts", %{conn: conn, user: user} do
    course = course_fixture(status: :published)

    for n <- 1..12 do
      payment_fixture(%{
        user_id: user.id,
        course_id: course.id,
        status: :successful,
        provider_reference: "RC-#{String.pad_leading(to_string(n), 2, "0")}"
      })
    end

    {:ok, lv, html} = live(conn, ~p"/receipts")
    assert html =~ "Page 1 of 2"

    html = lv |> element("a", "Next") |> render_click()
    assert_patch(lv, ~p"/receipts?page=2")
    assert html =~ "Page 2 of 2"
  end
end
