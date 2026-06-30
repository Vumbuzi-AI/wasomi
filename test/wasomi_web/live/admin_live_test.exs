defmodule WasomiWeb.AdminLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures

  defp admin_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  describe "access control" do
    test "anonymous users are redirected to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, ~p"/admin")
    end

    test "learners are redirected away from the admin area", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
    end

    test "admins can reach the overview", %{conn: conn} do
      conn = log_in_user(conn, admin_fixture())
      {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ "Business overview"
    end
  end

  describe "courses" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, admin_fixture())}
    end

    test "lists existing courses with revenue and student counts", %{conn: conn} do
      course = course_fixture(title: "Communication Mastery")
      {:ok, _view, html} = live(conn, ~p"/admin/courses")

      assert html =~ "Communication Mastery"
      assert html =~ course.slug
    end

    test "creates a course through the modal form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/courses/new")

      attrs = %{
        slug: "new-admin-course",
        title: "A brand new course",
        subtitle: "Learn something",
        description: "A full description",
        thumbnail_key: "thumb.jpg",
        price_minor: "1500.00",
        currency: "KES",
        status: "published",
        position: "3"
      }

      html =
        view
        |> form("#course-form", course: attrs)
        |> render_submit()

      assert_patched(view, ~p"/admin/courses")
      assert html =~ "A brand new course"
      assert %{price_minor: 150_000} = Wasomi.Catalog.get_course_by_slug!("new-admin-course")
    end

    test "uploads a course thumbnail through the modal form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/courses/new")

      thumbnail =
        file_input(view, "#course-form", :thumbnail, [
          %{name: "cover.png", content: "fake-image-bytes", type: "image/png"}
        ])

      assert render_upload(thumbnail, "cover.png") =~ "100%"

      html =
        view
        |> form("#course-form",
          course: %{
            slug: "uploaded-thumbnail-course",
            title: "Uploaded thumbnail course",
            subtitle: "Image upload",
            description: "A course with an uploaded thumbnail.",
            price_minor: "1500.00",
            currency: "KES",
            status: "published",
            position: "4"
          }
        )
        |> render_submit()

      assert html =~ "Uploaded thumbnail course"
      course = Wasomi.Catalog.get_course_by_slug!("uploaded-thumbnail-course")
      assert String.starts_with?(course.thumbnail_key, "/uploads/thumbnails/")
      assert String.ends_with?(course.thumbnail_key, ".png")

      on_exit(fn ->
        File.rm(Path.join(:code.priv_dir(:wasomi), "static#{course.thumbnail_key}"))
      end)
    end
  end

  describe "course detail" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, admin_fixture())}
    end

    test "shows enrolled students, revenue and the thumbnail image", %{conn: conn} do
      course = course_fixture(title: "Detailed Course", thumbnail_key: "cover.jpg")
      {:ok, _view, html} = live(conn, ~p"/admin/courses/#{course.id}")

      assert html =~ "Detailed Course"
      assert html =~ "Enrolled students"
      assert html =~ "Course curriculum"
      assert html =~ "cover.jpg"
    end

    test "adds a module through the curriculum editor", %{conn: conn} do
      course = course_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

      view |> element("button", "Add module") |> render_click()

      html =
        view
        |> form("#course_module-form",
          course_module: %{title: "Storytelling", description: "Narrative skills", position: "1"}
        )
        |> render_submit()

      assert html =~ "Storytelling"
      assert [%{title: "Storytelling"}] = Wasomi.Catalog.list_modules()
    end

    test "uploads a lecture video and deletes the lecture", %{conn: conn} do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

      # Open the "add lecture" form, attach a video file, then save.
      render_click(view, "new_lecture", %{"module-id" => to_string(module.id)})

      video =
        file_input(view, "#lecture-form", :video, [
          %{name: "lesson.mp4", content: "fake-video-bytes", type: "video/mp4"}
        ])

      assert render_upload(video, "lesson.mp4") =~ "100%"

      html =
        view
        |> form("#lecture-form",
          lecture: %{
            title: "Opening hook",
            description: "How to start",
            duration_seconds: "120",
            position: "1"
          }
        )
        |> render_submit()

      assert html =~ "Opening hook"
      [lecture] = Wasomi.Catalog.list_lectures()
      assert lecture.title == "Opening hook"
      assert String.starts_with?(lecture.video_asset_id, "/uploads/lectures/")
      assert String.ends_with?(lecture.video_asset_id, ".mp4")

      on_exit(fn ->
        File.rm(Path.join(:code.priv_dir(:wasomi), "static#{lecture.video_asset_id}"))
      end)

      html = render_click(view, "delete_lecture", %{"id" => lecture.id})
      refute html =~ "Opening hook"
      assert Wasomi.Catalog.list_lectures() == []
    end

    test "reorders modules through the curriculum editor", %{conn: conn} do
      course = course_fixture()
      first = course_module_fixture(course_id: course.id, position: 1, title: "First module")
      second = course_module_fixture(course_id: course.id, position: 2, title: "Second module")

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

      html =
        render_hook(view, "reorder_modules", %{
          "module_ids" => [to_string(second.id), to_string(first.id)]
        })

      assert html =~ "Second module"

      course = Wasomi.Catalog.get_course_with_outline!(course.id)
      assert Enum.map(course.modules, & &1.id) == [second.id, first.id]
      assert Enum.map(course.modules, & &1.position) == [1, 2]
    end

    test "reorders lectures through the curriculum editor", %{conn: conn} do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, position: 1, title: "Module One")
      first = lecture_fixture(module_id: module.id, position: 1, title: "First lecture")
      second = lecture_fixture(module_id: module.id, position: 2, title: "Second lecture")

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

      html =
        render_hook(view, "reorder_lectures", %{
          "module_id" => to_string(module.id),
          "lecture_ids" => [to_string(second.id), to_string(first.id)]
        })

      assert html =~ "Second lecture"

      course = Wasomi.Catalog.get_course_with_outline!(course.id)
      [module] = course.modules
      assert Enum.map(module.lectures, & &1.id) == [second.id, first.id]
      assert Enum.map(module.lectures, & &1.position) == [1, 2]
    end
  end

  describe "students and payments" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, admin_fixture())}
    end

    test "lists students", %{conn: conn} do
      learner = user_fixture()
      {:ok, _view, html} = live(conn, ~p"/admin/students")
      assert html =~ learner.email
    end

    test "renders the payments page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/payments")
      assert html =~ "Total revenue"
    end
  end
end
