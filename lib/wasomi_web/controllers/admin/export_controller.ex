defmodule WasomiWeb.Admin.ExportController do
  @moduledoc """
  Streams admin data exports as CSV without buffering the whole dataset in
  memory. `Repo.stream/2` pulls rows from the database in small batches
  inside a single transaction, and each batch is written out via
  `Plug.Conn.chunk/2` as soon as it's encoded — the row count never
  determines memory usage, only how long the response takes.
  """

  use WasomiWeb, :controller

  import Ecto.Query, warn: false

  alias NimbleCSV.RFC4180, as: CSV
  alias Wasomi.Assessments.QuizSubmission
  alias Wasomi.Catalog.{Course, CourseModule}
  alias Wasomi.Enrollments.Enrollment
  alias Wasomi.Payments.Payment
  alias Wasomi.Repo

  @batch_size 500

  @exports ~w(enrollments payments quiz_results)

  def show(conn, %{"type" => type} = params) when type in @exports do
    filters = parse_filters(params)
    filename = filename(type, filters)

    conn =
      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_chunked(200)

    # Bounded but generous — large enough for a genuinely large export to
    # finish, finite so a stalled client connection can't hold a DB
    # connection open indefinitely and starve the pool.
    {:ok, conn} =
      Repo.transaction(
        fn -> stream_rows(conn, type, filters) end,
        timeout: :timer.minutes(10)
      )

    conn
  end

  def show(conn, _params) do
    conn
    |> put_status(:not_found)
    |> text("Unknown export type. Expected one of: #{Enum.join(@exports, ", ")}")
  end

  defp stream_rows(conn, type, filters) do
    # A client can disconnect mid-download (closed tab, cancelled
    # download) at any point — chunk/2 then returns {:error, :closed}
    # rather than raising, so reduce_while stops cleanly instead of
    # crashing the transaction on a hard {:ok, conn} match.
    case chunk(conn, CSV.dump_to_iodata([header_row(type)])) do
      {:ok, conn} -> stream_body(conn, type, filters)
      {:error, _reason} -> conn
    end
  end

  defp stream_body(conn, type, filters) do
    type
    |> query(filters)
    |> Repo.stream(max_rows: @batch_size)
    |> Stream.map(&to_row(type, &1))
    |> Stream.chunk_every(@batch_size)
    |> Enum.reduce_while(conn, fn rows, conn ->
      case chunk(conn, CSV.dump_to_iodata(rows)) do
        {:ok, conn} -> {:cont, conn}
        {:error, _reason} -> {:halt, conn}
      end
    end)
  end

  # -- CSV headers ------------------------------------------------------------

  defp header_row("enrollments"),
    do: ~w(id student_email student_name course status enrolled_at activated_at)

  defp header_row("payments"),
    do: ~w(id student_email course provider reference amount currency status paid_at inserted_at)

  defp header_row("quiz_results"),
    do: ~w(id student_email course module quiz score_percent passed submitted_at)

  # -- queries ------------------------------------------------------------------

  defp query("enrollments", filters) do
    Enrollment
    |> join(:inner, [e], u in assoc(e, :user))
    |> join(:inner, [e], c in assoc(e, :course))
    |> filter_direct_course(filters)
    |> filter_range(:enrolled_at, filters)
    |> order_by([e], asc: e.id)
    |> select([e, u, c], %{
      id: e.id,
      student_email: u.email,
      student_name: u.name,
      course: c.title,
      status: e.status,
      enrolled_at: e.enrolled_at,
      activated_at: e.activated_at
    })
  end

  defp query("payments", filters) do
    Payment
    |> join(:left, [p], u in assoc(p, :user))
    |> join(:left, [p], c in assoc(p, :course))
    |> filter_direct_course(filters)
    |> filter_payment_range(filters)
    |> order_by([p], asc: p.id)
    |> select([p, u, c], %{
      id: p.id,
      student_email: u.email,
      course: c.title,
      provider: p.provider,
      reference: p.provider_reference,
      amount_minor: p.amount_minor,
      currency: p.currency,
      status: p.status,
      paid_at: p.paid_at,
      inserted_at: p.inserted_at
    })
  end

  defp query("quiz_results", filters) do
    QuizSubmission
    |> join(:inner, [s], u in assoc(s, :user))
    |> join(:inner, [s], q in assoc(s, :quiz))
    |> join(:inner, [s, u, q], m in CourseModule, on: m.id == q.module_id)
    |> join(:inner, [s, u, q, m], c in assoc(m, :course))
    |> filter_quiz_course(filters)
    |> filter_range(:submitted_at, filters)
    |> order_by([s], asc: s.id)
    |> select([s, u, q, m, c], %{
      id: s.id,
      student_email: u.email,
      course: c.title,
      module: m.title,
      quiz: q.title,
      score_percent: s.score_percent,
      passed: s.passed,
      submitted_at: s.submitted_at
    })
  end

  # -- row formatting -----------------------------------------------------------

  defp to_row("enrollments", row) do
    [
      row.id,
      row.student_email,
      row.student_name,
      row.course,
      row.status,
      row.enrolled_at,
      row.activated_at
    ]
    |> Enum.map(&csv_cell/1)
  end

  defp to_row("payments", row) do
    [
      row.id,
      row.student_email,
      row.course,
      row.provider,
      row.reference,
      major_amount(row.amount_minor),
      row.currency,
      row.status,
      row.paid_at,
      row.inserted_at
    ]
    |> Enum.map(&csv_cell/1)
  end

  defp to_row("quiz_results", row) do
    [
      row.id,
      row.student_email,
      row.course,
      row.module,
      row.quiz,
      row.score_percent,
      row.passed,
      row.submitted_at
    ]
    |> Enum.map(&csv_cell/1)
  end

  # -- filename ---------------------------------------------------------------

  # Reuses the course's existing public slug (same one used in course URLs)
  # rather than re-deriving one from the title, so a course-scoped export
  # is easy to tell apart from the rest — e.g.
  defp filename(type, filters) do
    course_part =
      case filters.course_id && Repo.get(Course, filters.course_id) do
        %Course{slug: slug} -> "#{slug}_"
        _ -> ""
      end

    date_part = date_suffix(filters.from, filters.to)

    "wasomi_#{type}_#{course_part}#{date_part}.csv"
  end

  defp date_suffix(%Date{} = from, %Date{} = to), do: "#{from}_to_#{to}"
  defp date_suffix(%Date{} = from, nil), do: "from_#{from}"
  defp date_suffix(nil, %Date{} = to), do: "to_#{to}"
  defp date_suffix(nil, nil), do: "#{Date.utc_today()}"

  # -- filters --------------------------------------------------------------

  defp parse_filters(params) do
    %{
      course_id: parse_id(params["course_id"]),
      from: parse_date(params["from"]),
      to: parse_date(params["to"])
    }
  end

  defp parse_id(nil), do: nil
  defp parse_id(""), do: nil

  defp parse_id(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  # `course_id` lives directly on binding 0 for enrollments/payments.
  defp filter_direct_course(query, %{course_id: nil}), do: query
  defp filter_direct_course(query, %{course_id: id}), do: where(query, [x], x.course_id == ^id)

  # quiz_results joins up to the course as its 5th binding (s, u, q, m, c).
  defp filter_quiz_course(query, %{course_id: nil}), do: query

  defp filter_quiz_course(query, %{course_id: id}),
    do: where(query, [_s, _u, _q, _m, c], c.id == ^id)

  # Binding 0 is always the exported table itself across every query here.
  defp filter_range(query, field, filters) do
    query
    |> filter_from(field, start_of_day(filters.from))
    |> filter_to(field, end_of_day(filters.to))
  end

  defp filter_from(query, _field, nil), do: query
  defp filter_from(query, field, from), do: where(query, [x], field(x, ^field) >= ^from)

  defp filter_to(query, _field, nil), do: query
  defp filter_to(query, field, to), do: where(query, [x], field(x, ^field) <= ^to)

  defp filter_payment_range(query, filters) do
    query
    |> filter_payment_from(start_of_day(filters.from))
    |> filter_payment_to(end_of_day(filters.to))
  end

  defp filter_payment_from(query, nil), do: query

  defp filter_payment_from(query, from),
    do: where(query, [p], fragment("coalesce(?, ?)", p.paid_at, p.inserted_at) >= ^from)

  defp filter_payment_to(query, nil), do: query

  defp filter_payment_to(query, to),
    do: where(query, [p], fragment("coalesce(?, ?)", p.paid_at, p.inserted_at) <= ^to)

  defp start_of_day(nil), do: nil
  defp start_of_day(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  defp end_of_day(nil), do: nil
  defp end_of_day(%Date{} = date), do: DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

  # -- cell formatting --------------------------------------------------------

  defp major_amount(nil), do: nil

  defp major_amount(amount_minor) do
    amount_minor
    |> Decimal.new()
    |> Decimal.div(Decimal.new(100))
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp csv_cell(nil), do: ""
  defp csv_cell(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp csv_cell(value) when is_atom(value), do: Atom.to_string(value)
  defp csv_cell(value), do: value |> to_string() |> neutralize_formula()

  # A cell starting with =, +, -, or @ can be interpreted as a formula by
  # Excel/Sheets when the CSV is opened — several of these columns (student
  # name, course/module/quiz titles) are ultimately user-authored text, so
  # prefix with a tab to neutralize without altering the visible value.
  defp neutralize_formula(<<lead, _::binary>> = value) when lead in [?=, ?+, ?-, ?@],
    do: "\t" <> value

  defp neutralize_formula(value), do: value
end
