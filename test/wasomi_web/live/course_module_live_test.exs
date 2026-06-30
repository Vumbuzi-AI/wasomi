defmodule WasomiWeb.CourseModuleLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.CatalogFixtures

  @create_attrs %{position: 42, description: "some description", title: "some title"}
  @update_attrs %{
    position: 43,
    description: "some updated description",
    title: "some updated title"
  }
  @invalid_attrs %{position: nil, description: nil, title: nil}

  defp create_course_module(_) do
    course_module = course_module_fixture()
    %{course_module: course_module}
  end

  describe "Index" do
    setup [:create_course_module]

    test "lists all modules", %{conn: conn, course_module: course_module} do
      {:ok, _index_live, html} = live(conn, ~p"/modules")

      assert html =~ "Listing Modules"
      assert html =~ course_module.description
    end

    test "saves new course_module", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/modules")

      assert index_live |> element("a", "New Course module") |> render_click() =~
               "New Course module"

      assert_patch(index_live, ~p"/modules/new")

      assert index_live
             |> form("#course_module-form", course_module: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#course_module-form", course_module: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/modules")

      html = render(index_live)
      assert html =~ "Course module created successfully"
      assert html =~ "some description"
    end

    test "updates course_module in listing", %{conn: conn, course_module: course_module} do
      {:ok, index_live, _html} = live(conn, ~p"/modules")

      assert index_live |> element("#modules-#{course_module.id} a", "Edit") |> render_click() =~
               "Edit Course module"

      assert_patch(index_live, ~p"/modules/#{course_module}/edit")

      assert index_live
             |> form("#course_module-form", course_module: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#course_module-form", course_module: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/modules")

      html = render(index_live)
      assert html =~ "Course module updated successfully"
      assert html =~ "some updated description"
    end

    test "deletes course_module in listing", %{conn: conn, course_module: course_module} do
      {:ok, index_live, _html} = live(conn, ~p"/modules")

      assert index_live |> element("#modules-#{course_module.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#modules-#{course_module.id}")
    end
  end

  describe "Show" do
    setup [:create_course_module]

    test "displays course_module", %{conn: conn, course_module: course_module} do
      {:ok, _show_live, html} = live(conn, ~p"/modules/#{course_module}")

      assert html =~ "Show Course module"
      assert html =~ course_module.description
    end

    test "updates course_module within modal", %{conn: conn, course_module: course_module} do
      {:ok, show_live, _html} = live(conn, ~p"/modules/#{course_module}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Course module"

      assert_patch(show_live, ~p"/modules/#{course_module}/show/edit")

      assert show_live
             |> form("#course_module-form", course_module: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#course_module-form", course_module: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/modules/#{course_module}")

      html = render(show_live)
      assert html =~ "Course module updated successfully"
      assert html =~ "some updated description"
    end
  end
end
