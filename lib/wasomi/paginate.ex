defmodule Wasomi.Paginate do
  @moduledoc """
  Small limit/offset pagination helper for context list functions.

  Context functions build their (already filtered/ordered) `Ecto.Query` as
  usual and hand it to `paginate/3` instead of calling `Repo.all/1` directly.
  """

  import Ecto.Query

  alias Wasomi.Repo

  defstruct entries: [], page: 1, page_size: 20, total_count: 0, total_pages: 0

  @type t :: %__MODULE__{
          entries: list(),
          page: pos_integer(),
          page_size: pos_integer(),
          total_count: non_neg_integer(),
          total_pages: pos_integer()
        }

  @doc """
  Paginates `query` at `page`/`page_size`.

  `page` is clamped to `1..total_pages`, so an out-of-range page (e.g. from a
  stale bookmarked URL after rows are deleted) returns the nearest valid
  page's results instead of an empty page or an error.
  """
  def paginate(query, page, page_size)
      when is_integer(page) and is_integer(page_size) and page_size > 0 do
    total_count = Repo.aggregate(query, :count)

    entries = fn page ->
      query
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> Repo.all()
    end

    build(total_count, page, page_size, entries)
  end

  @doc """
  Paginates an already-fetched, already-ordered `list` at `page`/`page_size`
  in memory, rather than in the database.

  Use this for aggregate/grouped reports (e.g. per-course rollups) where the
  base dataset is bounded by something small like the course count, and
  computing it requires combining several separate context queries in
  Elixir (this codebase's established pattern for these — see
  `Wasomi.Payments.revenue_minor_by_course/0` and friends) rather than one
  join-prone SQL query.
  """
  def paginate_list(list, page, page_size)
      when is_list(list) and is_integer(page) and is_integer(page_size) and page_size > 0 do
    build(length(list), page, page_size, &Enum.slice(list, (&1 - 1) * page_size, page_size))
  end

  @doc """
  Parses a `page` query param into a positive integer, defaulting to `1`
  for anything absent, non-numeric, or less than 1 — the same fallback
  `paginate/3`/`paginate_list/3` apply internally, exposed for LiveViews
  to use while reading `handle_params/3` query strings.

  Query params are always a string or `nil` in practice, but this also
  accepts an already-parsed integer so it's safe to call defensively.
  """
  def parse_page(value) when is_integer(value) and value > 0, do: value
  def parse_page(value) when is_integer(value), do: 1

  def parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end

  def parse_page(_value), do: 1

  defp build(total_count, page, page_size, entries_fn) do
    total_pages = max(ceil(total_count / page_size), 1)
    page = page |> max(1) |> min(total_pages)

    %__MODULE__{
      entries: entries_fn.(page),
      page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages
    }
  end
end
