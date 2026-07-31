defmodule WasomiWeb.AdminLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
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
        title: "A brand new course",
        subtitle: "Learn something",
        description: "A full description",
        thumbnail_key: "thumb.jpg",
        price_minor: "1500.00",
        currency: "KES"
      }

      html =
        view
        |> form("#course-form", course: attrs)
        |> render_submit()

      assert_patched(view, ~p"/admin/courses")
      assert html =~ "A brand new course"

      # Status isn't a form field — the guarded publish flow (below) is the
      # only path to :published, so a freshly created course stays :draft.
      # Slug is auto-generated from title ("a-brand-new-course").
      assert %{price_minor: 150_000, status: :draft} =
               Wasomi.Catalog.get_course_by_slug!("a-brand-new-course")
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
            title: "Uploaded thumbnail course",
            subtitle: "Image upload",
            description: "A course with an uploaded thumbnail.",
            price_minor: "1500.00",
            currency: "KES"
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

    test "shows a draft-question reminder badge only when a module has unreviewed drafts", %{
      conn: conn
    } do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      {:ok, _view, html} = live(conn, ~p"/admin/courses/#{course.id}")

      refute html =~ "to review"

      quiz = quiz_fixture(%{module: module})
      question_fixture(%{quiz: quiz, status: :draft, position: 1})
      question_fixture(%{quiz: quiz, status: :draft, position: 2})

      {:ok, _view, html} = live(conn, ~p"/admin/courses/#{course.id}")

      assert html =~ "2 to review"
    end

    test "a module's quiz appears as a row in the curriculum once one exists", %{conn: conn} do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.id}")

      assert has_element?(view, "button", "Generate quiz (AI)")
      refute html =~ "published"

      quiz = quiz_fixture(%{module: module, title: "Module One Quiz"})
      question_fixture(%{quiz: quiz, status: :published, position: 1})
      question_fixture(%{quiz: quiz, status: :draft, position: 2})

      {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.id}")

      assert html =~ "Module One Quiz"
      assert html =~ "1 published"
      assert html =~ "1 to review"
      refute has_element?(view, "button", "Generate quiz (AI)")
      assert has_element?(view, "a[title='Manage quiz']")
    end

    test "deleting a module's quiz removes it and its questions", %{conn: conn} do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      quiz = quiz_fixture(%{module: module, title: "Module One Quiz"})
      question_fixture(%{quiz: quiz, status: :published, position: 1})

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

      assert has_element?(view, "button[title='Delete quiz']")
      refute has_element?(view, "#delete-quiz-modal")

      view
      |> element("button[title='Delete quiz']")
      |> render_click()

      assert has_element?(view, "#delete-quiz-modal")
      assert Wasomi.Assessments.get_quiz!(quiz.id)

      view
      |> element("#delete-quiz-modal button", "Delete quiz")
      |> render_click()

      refute has_element?(view, "#delete-quiz-modal")
      refute has_element?(view, "button[title='Delete quiz']")
      assert has_element?(view, "button", "Generate quiz (AI)")
      assert_raise Ecto.NoResultsError, fn -> Wasomi.Assessments.get_quiz!(quiz.id) end
    end

    test "cancelling the delete-quiz confirmation leaves the quiz intact", %{conn: conn} do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      quiz = quiz_fixture(%{module: module, title: "Module One Quiz"})

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

      view |> element("button[title='Delete quiz']") |> render_click()
      view |> element("#delete-quiz-modal button", "Cancel") |> render_click()

      refute has_element?(view, "#delete-quiz-modal")
      assert Wasomi.Assessments.get_quiz!(quiz.id)
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

    test "uploads a lecture resource file and handles invalid/no extension files gracefully", %{
      conn: conn
    } do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

      render_click(view, "new_lecture", %{"module-id" => to_string(module.id)})

      # 1. Invalid extension: .exe
      resources_exe =
        file_input(view, "#lecture-form", :resources, [
          %{name: "lesson.exe", content: "fake-exe-bytes", type: "application/x-msdownload"}
        ])

      assert {:error, [[_, %{reason: :not_accepted}]]} =
               render_upload(resources_exe, "lesson.exe")

      # 2. No extension at all
      resources_no_ext =
        file_input(view, "#lecture-form", :resources, [
          %{name: "lesson", content: "fake-bytes", type: "application/octet-stream"}
        ])

      assert {:error, [[_, %{reason: :not_accepted}]]} = render_upload(resources_no_ext, "lesson")
    end

    test "cancelling a resource upload triggers delete_upload/2 path", %{conn: conn} do
      previous_provider = Application.get_env(:wasomi, :storage_provider)
      previous_test_pid = Application.get_env(:wasomi, :test_pid)

      on_exit(fn ->
        Application.put_env(:wasomi, :storage_provider, previous_provider)
        Application.put_env(:wasomi, :test_pid, previous_test_pid)
      end)

      Application.put_env(:wasomi, :test_pid, self())
      Application.put_env(:wasomi, :storage_provider, WasomiWeb.AdminLiveTest.StorageMock)

      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

      render_click(view, "new_lecture", %{"module-id" => to_string(module.id)})

      # Upload a valid PDF file
      resources_pdf =
        file_input(view, "#lecture-form", :resources, [
          %{name: "lesson.pdf", content: "fake-pdf-bytes", type: "application/pdf"}
        ])

      # We render the upload which triggers presigning
      assert render_upload(resources_pdf, "lesson.pdf") =~ "100%"

      # Extract the ref of the entry from the rendered html to trigger cancel-upload event
      html = render(view)
      [_, ref] = Regex.run(~r/id="resource-upload-([^"]+)"/, html)

      # Trigger cancel-upload with that ref.
      view
      |> element("#resource-upload-#{ref} button[phx-click='cancel-upload']")
      |> render_click()

      # Assert that delete_upload_called message was sent to self
      assert_received :delete_upload_called
    end
  end

  describe "publishing a course" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, admin_fixture())}
    end

    test "publishing fails with a checklist when the course isn't ready", %{conn: conn} do
      course = course_fixture(status: :draft)
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/edit")

      html = view |> element("button", "Publish course") |> render_click()

      assert html =~ "ready to publish yet"
      assert html =~ "Add at least one module."
      assert Wasomi.Catalog.get_course!(course.id).status == :draft
    end

    test "publishing succeeds once every requirement is met", %{conn: conn} do
      course =
        course_fixture(status: :in_review, price_minor: 150_000, thumbnail_key: "cover.jpg")

      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1, video_asset_id: "abc123")

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/edit")

      view |> element("button", "Publish course") |> render_click()

      assert_patched(view, ~p"/admin/courses")
      assert Wasomi.Catalog.get_course!(course.id).status == :published
    end

    test "submit for review moves a draft course forward", %{conn: conn} do
      course = course_fixture(status: :draft)
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/edit")

      html = view |> element("button", "Submit for review") |> render_click()

      assert html =~ "in_review"
      assert Wasomi.Catalog.get_course!(course.id).status == :in_review
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

defmodule WasomiWeb.AdminLiveTest.StorageMock do
  def presign_upload(_user, attrs) do
    {:ok,
     %{
       url: "https://r2.example.test/presigned-url",
       key: "lectures/draft-123/lesson.pdf",
       public_url: "https://cdn.example.test/lectures/draft-123/lesson.pdf",
       content_type: attrs["content_type"] || "application/pdf"
     }}
  end

  def delete_upload(_user, _key) do
    if test_pid = Application.get_env(:wasomi, :test_pid) do
      send(test_pid, :delete_upload_called)
    end

    :ok
  end
end
