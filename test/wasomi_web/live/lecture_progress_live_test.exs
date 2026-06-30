defmodule WasomiWeb.LectureProgressLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.LearningFixtures

  @create_attrs %{
    status: :not_started,
    last_position_seconds: 42,
    completed_at: "2026-06-24T10:02:00Z"
  }
  @update_attrs %{
    status: :in_progress,
    last_position_seconds: 43,
    completed_at: "2026-06-25T10:02:00Z"
  }
  @invalid_attrs %{status: nil, last_position_seconds: nil, completed_at: nil}

  defp create_lecture_progress(_) do
    lecture_progress = lecture_progress_fixture()
    %{lecture_progress: lecture_progress}
  end

  describe "Index" do
    setup [:create_lecture_progress]

    test "lists all lecture_progress", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/lecture_progress")

      assert html =~ "Listing Lecture progress"
    end

    test "saves new lecture_progress", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/lecture_progress")

      assert index_live |> element("a", "New Lecture progress") |> render_click() =~
               "New Lecture progress"

      assert_patch(index_live, ~p"/lecture_progress/new")

      assert index_live
             |> form("#lecture_progress-form", lecture_progress: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#lecture_progress-form", lecture_progress: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/lecture_progress")

      html = render(index_live)
      assert html =~ "Lecture progress created successfully"
    end

    test "updates lecture_progress in listing", %{conn: conn, lecture_progress: lecture_progress} do
      {:ok, index_live, _html} = live(conn, ~p"/lecture_progress")

      assert index_live
             |> element("#lecture_progress-#{lecture_progress.id} a", "Edit")
             |> render_click() =~
               "Edit Lecture progress"

      assert_patch(index_live, ~p"/lecture_progress/#{lecture_progress}/edit")

      assert index_live
             |> form("#lecture_progress-form", lecture_progress: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#lecture_progress-form", lecture_progress: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/lecture_progress")

      html = render(index_live)
      assert html =~ "Lecture progress updated successfully"
    end

    test "deletes lecture_progress in listing", %{conn: conn, lecture_progress: lecture_progress} do
      {:ok, index_live, _html} = live(conn, ~p"/lecture_progress")

      assert index_live
             |> element("#lecture_progress-#{lecture_progress.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#lecture_progress-#{lecture_progress.id}")
    end
  end

  describe "Show" do
    setup [:create_lecture_progress]

    test "displays lecture_progress", %{conn: conn, lecture_progress: lecture_progress} do
      {:ok, _show_live, html} = live(conn, ~p"/lecture_progress/#{lecture_progress}")

      assert html =~ "Show Lecture progress"
    end

    test "updates lecture_progress within modal", %{
      conn: conn,
      lecture_progress: lecture_progress
    } do
      {:ok, show_live, _html} = live(conn, ~p"/lecture_progress/#{lecture_progress}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Lecture progress"

      assert_patch(show_live, ~p"/lecture_progress/#{lecture_progress}/show/edit")

      assert show_live
             |> form("#lecture_progress-form", lecture_progress: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#lecture_progress-form", lecture_progress: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/lecture_progress/#{lecture_progress}")

      html = render(show_live)
      assert html =~ "Lecture progress updated successfully"
    end
  end
end
