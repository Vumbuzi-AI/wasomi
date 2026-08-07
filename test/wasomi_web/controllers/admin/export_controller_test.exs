defmodule WasomiWeb.Admin.ExportControllerTest do
  use WasomiWeb.ConnCase

  import Ecto.Query
  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures
  import Wasomi.PaymentsFixtures

  alias Wasomi.Assessments.QuizSubmission
  alias Wasomi.Repo

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  defp submission_fixture(quiz, attrs) do
    {:ok, submission} =
      %QuizSubmission{}
      |> QuizSubmission.changeset(
        Enum.into(attrs, %{
          quiz_id: quiz.id,
          user_id: user_fixture().id,
          answers: %{},
          passed: true,
          submitted_at: ~U[2026-06-15 10:00:00Z]
        })
      )
      |> Repo.insert()

    submission
  end

  defp csv_rows(conn) do
    conn.resp_body
    |> NimbleCSV.RFC4180.parse_string(skip_headers: false)
  end

  describe "authorization" do
    test "redirects an unauthenticated request", %{conn: conn} do
      conn = get(conn, ~p"/admin/exports/enrollments")
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "redirects a non-admin learner", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/admin/exports/enrollments")
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "as an admin" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, admin_fixture())}
    end

    test "rejects an unknown export type", %{conn: conn} do
      conn = get(conn, ~p"/admin/exports/nonsense")
      assert conn.status == 404
    end

    test "streams enrollments as a chunked, date-stamped CSV", %{conn: conn} do
      course = course_fixture(title: "Applied Negotiation")
      student = user_fixture(name: "Amaya Otieno")
      enrollment_fixture(user_id: student.id, course_id: course.id, status: :active)

      conn = get(conn, ~p"/admin/exports/enrollments")

      assert conn.state == :chunked
      assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="wasomi_enrollments_#{Date.utc_today()}.csv")
             ]

      [header | rows] = csv_rows(conn)
      assert header == ~w(id student_email student_name course status enrolled_at activated_at)

      [row] = Enum.filter(rows, &(Enum.at(&1, 1) == student.email))
      assert Enum.at(row, 2) == "Amaya Otieno"
      assert Enum.at(row, 3) == "Applied Negotiation"
      assert Enum.at(row, 4) == "active"
    end

    test "streams payments with a Decimal-formatted major-unit amount", %{conn: conn} do
      course = course_fixture()
      payment = payment_fixture(course_id: course.id, status: :successful, amount_minor: 150_050)

      conn = get(conn, ~p"/admin/exports/payments")

      [_header | rows] = csv_rows(conn)
      [row] = Enum.filter(rows, &(&1 |> Enum.at(4) == payment.provider_reference))
      assert Enum.at(row, 5) == "1500.50"
    end

    test "streams quiz results joined up through module and course", %{conn: conn} do
      module = course_module_fixture(title: "Getting started")
      quiz = quiz_fixture(module: module, title: "Getting started quiz")
      submission = submission_fixture(quiz, %{score_percent: 82, passed: true})

      conn = get(conn, ~p"/admin/exports/quiz_results")

      [header | rows] = csv_rows(conn)
      assert header == ~w(id student_email course module quiz score_percent passed submitted_at)
      [row] = Enum.filter(rows, &(Enum.at(&1, 0) == to_string(submission.id)))
      assert Enum.at(row, 3) == "Getting started"
      assert Enum.at(row, 4) == "Getting started quiz"
      assert Enum.at(row, 5) == "82"
      assert Enum.at(row, 6) == "true"
    end

    test "course_id filter narrows enrollment rows to that course", %{conn: conn} do
      course_a = course_fixture(title: "Course A")
      course_b = course_fixture(title: "Course B")
      enrollment_fixture(user_id: user_fixture().id, course_id: course_a.id, status: :active)
      enrollment_fixture(user_id: user_fixture().id, course_id: course_b.id, status: :active)

      conn = get(conn, ~p"/admin/exports/enrollments?course_id=#{course_a.id}")

      [_header | rows] = csv_rows(conn)
      assert Enum.all?(rows, &(Enum.at(&1, 3) == "Course A"))
      assert rows != []
    end

    test "course_id filter names the file after that course's slug", %{conn: conn} do
      course = course_fixture(title: "Course A")

      conn = get(conn, ~p"/admin/exports/payments?course_id=#{course.id}")

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="wasomi_payments_#{course.slug}_#{Date.utc_today()}.csv")
             ]
    end

    test "an unrecognized course_id falls back to the unscoped filename", %{conn: conn} do
      conn = get(conn, ~p"/admin/exports/payments?course_id=999999")

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="wasomi_payments_#{Date.utc_today()}.csv")
             ]
    end

    test "date range filter excludes payments outside the window", %{conn: conn} do
      course = course_fixture()

      in_range =
        payment_fixture(
          course_id: course.id,
          status: :successful,
          provider_reference: "in-range",
          inserted_at_override: ~U[2026-06-15 10:00:00Z]
        )

      out_of_range =
        payment_fixture(
          course_id: course.id,
          status: :successful,
          provider_reference: "out-of-range",
          paid_at: ~U[2026-07-15 10:00:00Z]
        )

      Repo.update_all(
        from(p in Wasomi.Payments.Payment, where: p.id == ^in_range.id),
        set: [inserted_at: ~U[2026-06-15 10:00:00Z]]
      )

      Repo.update_all(
        from(p in Wasomi.Payments.Payment, where: p.id == ^out_of_range.id),
        set: [inserted_at: ~U[2026-07-15 10:00:00Z]]
      )

      conn = get(conn, ~p"/admin/exports/payments?from=2026-06-01&to=2026-06-30")

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="wasomi_payments_2026-06-01_to_2026-06-30.csv")
             ]

      [_header | rows] = csv_rows(conn)
      references = Enum.map(rows, &Enum.at(&1, 4))
      assert "in-range" in references
      refute "out-of-range" in references
    end

    test "neutralizes a formula-like student name to prevent CSV injection", %{conn: conn} do
      course = course_fixture()
      student = user_fixture(name: "=cmd|'/c calc'!A0")
      enrollment_fixture(user_id: student.id, course_id: course.id, status: :active)

      conn = get(conn, ~p"/admin/exports/enrollments")

      [_header | rows] = csv_rows(conn)
      [row] = Enum.filter(rows, &(Enum.at(&1, 1) == student.email))
      assert Enum.at(row, 2) == "\t=cmd|'/c calc'!A0"
    end
  end
end
