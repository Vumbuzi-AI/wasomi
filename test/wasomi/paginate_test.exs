defmodule Wasomi.PaginateTest do
  use Wasomi.DataCase

  import Wasomi.CatalogFixtures

  alias Wasomi.Catalog.Course
  alias Wasomi.Paginate

  import Ecto.Query

  defp base_query, do: from(c in Course, order_by: [asc: c.inserted_at, asc: c.id])

  test "paginates a query, returning entries, counts, and page boundaries" do
    Enum.each(1..5, fn n -> course_fixture(title: "Course #{n}") end)

    page = Paginate.paginate(base_query(), 1, 2)

    assert page.total_count == 5
    assert page.total_pages == 3
    assert page.page == 1
    assert length(page.entries) == 2
  end

  test "returns the last (partial) page correctly" do
    Enum.each(1..5, fn n -> course_fixture(title: "Course #{n}") end)

    page = Paginate.paginate(base_query(), 3, 2)

    assert page.page == 3
    assert length(page.entries) == 1
  end

  test "clamps a page number beyond the last page down to the last page" do
    Enum.each(1..3, fn n -> course_fixture(title: "Course #{n}") end)

    page = Paginate.paginate(base_query(), 99, 2)

    assert page.page == 2
    assert page.total_pages == 2
    assert length(page.entries) == 1
  end

  test "clamps a page number below 1 up to 1" do
    course_fixture()

    page = Paginate.paginate(base_query(), 0, 10)

    assert page.page == 1
  end

  test "an empty result set has total_pages 1 and no entries" do
    page = Paginate.paginate(base_query(), 1, 10)

    assert page.total_count == 0
    assert page.total_pages == 1
    assert page.page == 1
    assert page.entries == []
  end

  test "raises for a non-integer page instead of silently misbehaving" do
    assert_raise FunctionClauseError, fn -> Paginate.paginate(base_query(), "1", 10) end
    assert_raise FunctionClauseError, fn -> Paginate.paginate(base_query(), nil, 10) end
  end

  describe "paginate_list/3" do
    test "paginates an in-memory list the same way as a query" do
      page = Paginate.paginate_list(Enum.to_list(1..5), 1, 2)

      assert page.entries == [1, 2]
      assert page.total_count == 5
      assert page.total_pages == 3
      assert page.page == 1
    end

    test "returns the last (partial) page correctly" do
      page = Paginate.paginate_list(Enum.to_list(1..5), 3, 2)

      assert page.entries == [5]
      assert page.page == 3
    end

    test "clamps an out-of-range page down to the last page" do
      page = Paginate.paginate_list(Enum.to_list(1..3), 99, 2)

      assert page.entries == [3]
      assert page.page == 2
    end

    test "an empty list has total_pages 1 and no entries" do
      page = Paginate.paginate_list([], 1, 10)

      assert page.total_count == 0
      assert page.total_pages == 1
      assert page.entries == []
    end

    test "raises for a non-integer page instead of silently misbehaving" do
      assert_raise FunctionClauseError, fn -> Paginate.paginate_list([1, 2, 3], "1", 2) end
      assert_raise FunctionClauseError, fn -> Paginate.paginate_list([1, 2, 3], nil, 2) end
    end
  end

  describe "parse_page/1" do
    test "parses a valid page number" do
      assert Paginate.parse_page("3") == 3
    end

    test "defaults to 1 for nil, non-numeric, zero, or negative values" do
      assert Paginate.parse_page(nil) == 1
      assert Paginate.parse_page("bogus") == 1
      assert Paginate.parse_page("0") == 1
      assert Paginate.parse_page("-5") == 1
    end

    test "also accepts an already-parsed integer instead of crashing" do
      assert Paginate.parse_page(3) == 3
      assert Paginate.parse_page(0) == 1
      assert Paginate.parse_page(-5) == 1
    end
  end
end
