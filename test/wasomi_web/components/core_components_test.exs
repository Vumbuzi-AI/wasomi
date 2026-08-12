defmodule WasomiWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component

  alias WasomiWeb.CoreComponents

  defp render_paginated_table(assigns) do
    render_component(&paginated_table_wrapper/1, assigns)
  end

  defp paginated_table_wrapper(assigns) do
    ~H"""
    <CoreComponents.paginated_table page={@page} total_pages={@total_pages} path_fn={@path_fn}>
      the-course-grid
    </CoreComponents.paginated_table>
    """
  end

  describe "search_input/1" do
    test "debounces via phx-debounce and pushes the configured event/param name" do
      html =
        render_component(&CoreComponents.search_input/1, %{
          value: "gs1",
          name: "q",
          event: "search",
          placeholder: "Search course or slug",
          debounce: 300
        })

      assert html =~ ~s(phx-change="search")
      assert html =~ ~s(phx-debounce="300")
      assert html =~ ~s(name="q")
      assert html =~ ~s(value="gs1")
      assert html =~ "Search course or slug"
    end

    test "defaults to a 300ms debounce and q/search naming" do
      html = render_component(&CoreComponents.search_input/1, %{})

      assert html =~ ~s(phx-debounce="300")
      assert html =~ ~s(name="q")
      assert html =~ ~s(phx-change="search")
    end
  end

  describe "paginated_table/1" do
    test "shows both Previous and Next on a middle page" do
      html =
        render_paginated_table(%{page: 2, total_pages: 3, path_fn: &"/admin/courses?page=#{&1}"})

      assert html =~ "Previous"
      assert html =~ "Next"
      assert html =~ "Page 2 of 3"
    end

    test "hides Previous on the first page" do
      html =
        render_paginated_table(%{page: 1, total_pages: 3, path_fn: &"/admin/courses?page=#{&1}"})

      refute html =~ "Previous"
      assert html =~ "Next"
    end

    test "hides Next on the last page" do
      html =
        render_paginated_table(%{page: 3, total_pages: 3, path_fn: &"/admin/courses?page=#{&1}"})

      assert html =~ "Previous"
      refute html =~ "Next"
    end

    test "renders no pagination nav at all for a single page" do
      html =
        render_paginated_table(%{page: 1, total_pages: 1, path_fn: &"/admin/courses?page=#{&1}"})

      refute html =~ "Previous"
      refute html =~ "Next"
      refute html =~ "Page 1 of 1"
    end

    test "renders the inner block content" do
      html =
        render_paginated_table(%{page: 1, total_pages: 1, path_fn: &"/admin/courses?page=#{&1}"})

      assert html =~ "the-course-grid"
    end
  end
end
