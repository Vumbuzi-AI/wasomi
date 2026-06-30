defmodule WasomiWeb.LectureLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.CatalogFixtures

  @create_attrs %{
    position: 42,
    description: "some description",
    title: "some title",
    video_provider: :mux,
    video_asset_id: "some video_asset_id",
    duration_seconds: 42
  }
  @update_attrs %{
    position: 43,
    description: "some updated description",
    title: "some updated title",
    video_provider: :cloudflare,
    video_asset_id: "some updated video_asset_id",
    duration_seconds: 43
  }
  @invalid_attrs %{
    position: nil,
    description: nil,
    title: nil,
    video_provider: nil,
    video_asset_id: nil,
    duration_seconds: nil
  }

  defp create_lecture(_) do
    lecture = lecture_fixture()
    %{lecture: lecture}
  end

  describe "Index" do
    setup [:create_lecture]

    test "lists all lectures", %{conn: conn, lecture: lecture} do
      {:ok, _index_live, html} = live(conn, ~p"/lectures")

      assert html =~ "Listing Lectures"
      assert html =~ lecture.description
    end

    test "saves new lecture", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/lectures")

      assert index_live |> element("a", "New Lecture") |> render_click() =~
               "New Lecture"

      assert_patch(index_live, ~p"/lectures/new")

      assert index_live
             |> form("#lecture-form", lecture: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#lecture-form", lecture: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/lectures")

      html = render(index_live)
      assert html =~ "Lecture created successfully"
      assert html =~ "some description"
    end

    test "updates lecture in listing", %{conn: conn, lecture: lecture} do
      {:ok, index_live, _html} = live(conn, ~p"/lectures")

      assert index_live |> element("#lectures-#{lecture.id} a", "Edit") |> render_click() =~
               "Edit Lecture"

      assert_patch(index_live, ~p"/lectures/#{lecture}/edit")

      assert index_live
             |> form("#lecture-form", lecture: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#lecture-form", lecture: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/lectures")

      html = render(index_live)
      assert html =~ "Lecture updated successfully"
      assert html =~ "some updated description"
    end

    test "deletes lecture in listing", %{conn: conn, lecture: lecture} do
      {:ok, index_live, _html} = live(conn, ~p"/lectures")

      assert index_live |> element("#lectures-#{lecture.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#lectures-#{lecture.id}")
    end
  end

  describe "Show" do
    setup [:create_lecture]

    test "displays lecture", %{conn: conn, lecture: lecture} do
      {:ok, _show_live, html} = live(conn, ~p"/lectures/#{lecture}")

      assert html =~ "Show Lecture"
      assert html =~ lecture.description
    end

    test "updates lecture within modal", %{conn: conn, lecture: lecture} do
      {:ok, show_live, _html} = live(conn, ~p"/lectures/#{lecture}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Lecture"

      assert_patch(show_live, ~p"/lectures/#{lecture}/show/edit")

      assert show_live
             |> form("#lecture-form", lecture: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#lecture-form", lecture: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/lectures/#{lecture}")

      html = render(show_live)
      assert html =~ "Lecture updated successfully"
      assert html =~ "some updated description"
    end
  end
end
