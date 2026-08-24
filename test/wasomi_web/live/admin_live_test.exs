defmodule WasomiWeb.AdminLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures

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

    test "renders stat cards reflecting course, enrollment, and revenue state", %{conn: conn} do
      course_fixture(status: :draft)
      published = course_fixture(status: :published)
      enrollment_fixture(user_id: user_fixture().id, course_id: published.id, status: :active)

      {:ok, _view, html} = live(conn, ~p"/admin/courses")

      assert html =~ "Total courses"
      assert html =~ ~r/Total courses.*?>\s*2\s*</s
      assert html =~ ~r/Published.*?>\s*1\s*</s
      assert html =~ ~r/Draft.*?>\s*1\s*</s
      assert html =~ "Learners"
    end

    test "filters the course grid by status", %{conn: conn} do
      draft = course_fixture(title: "Draft Course", status: :draft)
      published = course_fixture(title: "Published Course", status: :published)

      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      html =
        view
        |> element(~s(a[href="/admin/courses?status=published"]))
        |> render_click()

      assert html =~ published.title
      refute html =~ draft.title
      assert_patched(view, ~p"/admin/courses?status=published")
    end

    test "searches the course grid by title", %{conn: conn} do
      match = course_fixture(title: "Communication Mastery")
      other = course_fixture(title: "Data Analysis")

      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      html =
        view
        |> form("form[phx-change=search]", %{"q" => "Communication"})
        |> render_change()

      assert html =~ match.title
      refute html =~ other.title
    end

    test "paginates the course grid, 9 per page", %{conn: conn} do
      Enum.each(1..10, fn n -> course_fixture(title: "Course #{n}") end)

      {:ok, view, html} = live(conn, ~p"/admin/courses")

      assert html =~ "10 courses"
      assert html =~ "Page 1 of 2"
      refute html =~ "Previous"
      assert html =~ "Next"

      html =
        view
        |> element(~s(a[href="/admin/courses?page=2"]))
        |> render_click()

      assert html =~ "Page 2 of 2"
      assert html =~ "Previous"
      refute html =~ "Next"
      assert_patched(view, ~p"/admin/courses?page=2")
    end

    test "shows a no-matches empty state distinct from the no-courses-yet state", %{conn: conn} do
      course_fixture(title: "Communication Mastery")

      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      html =
        view
        |> form("form[phx-change=search]", %{"q" => "nonexistent course"})
        |> render_change()

      assert html =~ "No matching courses"
      refute html =~ "No courses yet"
    end

    test "creates a course through the modal form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/courses/new")

      attrs = %{
        title: "A brand new course",
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

    test "creates a free course through the modal form setting price_minor to nil", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/courses/new")

      attrs = %{
        title: "A free course",
        description: "A free description",
        thumbnail_key: "thumb.jpg",
        is_free: "true",
        currency: "KES"
      }

      html =
        view
        |> form("#course-form", course: attrs)
        |> render_submit()

      assert_patched(view, ~p"/admin/courses")
      assert html =~ "A free course"

      created = Wasomi.Catalog.get_course_by_slug!("a-free-course")
      assert created.is_free == true
      assert created.price_minor == nil
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

    test "publishes a ready draft course from the list row", %{conn: conn} do
      course = course_fixture(status: :draft, price_minor: 150_000, thumbnail_key: "cover.jpg")
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1, video_asset_id: "abc123")

      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      html =
        view
        |> element("button[title='Publish course']")
        |> render_click()

      assert html =~ "now visible in the public catalog"
      assert Wasomi.Catalog.get_course!(course.id).status == :published
      refute has_element?(view, "button[title='Publish course']")
    end

    test "shows the publish checklist modal when publishing an unready course from the list row",
         %{conn: conn} do
      course = course_fixture(status: :draft)
      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      refute has_element?(view, "#publish-checklist-modal")

      html =
        view
        |> element("button[title='Publish course']")
        |> render_click()

      assert has_element?(view, "#publish-checklist-modal")
      assert html =~ "isn&#39;t ready to publish yet"
      assert html =~ "Curriculum"
      assert html =~ "Add at least one module."
      # Price/thumbnail have fixture defaults, so those stages pass —
      # confirms the checklist shows the full picture, not just failures.
      refute html =~ "Set a course price."
      assert Wasomi.Catalog.get_course!(course.id).status == :draft

      view |> element("#publish-checklist-modal button", "Close") |> render_click()
      refute has_element?(view, "#publish-checklist-modal")
    end

    test "archives a published course from the list row through the confirm dialog", %{
      conn: conn
    } do
      course = course_fixture(status: :published, title: "Retiring Course")
      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      refute has_element?(view, "#archive-course-modal")

      view |> element("button[title='Archive course']") |> render_click()

      assert has_element?(view, "#archive-course-modal")
      assert render(view) =~ "No enrolled learners are affected"

      html = view |> element("#archive-course-modal button", "Archive") |> render_click()

      refute has_element?(view, "#archive-course-modal")
      assert html =~ "no longer visible in the public catalog"
      assert Wasomi.Catalog.get_course!(course.id).status == :archived
    end

    test "cancelling the archive confirmation leaves the course published", %{conn: conn} do
      course = course_fixture(status: :published)
      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      view |> element("button[title='Archive course']") |> render_click()
      view |> element("#archive-course-modal button", "Cancel") |> render_click()

      refute has_element?(view, "#archive-course-modal")
      assert Wasomi.Catalog.get_course!(course.id).status == :published
    end

    test "an archived course shows no status-action icon on the list row", %{conn: conn} do
      _course = course_fixture(status: :archived)
      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      refute has_element?(view, "button[title='Publish course']")
      refute has_element?(view, "button[title='Archive course']")
      assert has_element?(view, "a[title='Edit course']")
    end
  end

  describe "course detail" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, admin_fixture())}
    end

    defp submit_basics(view, title, description) do
      view
      |> form("#lecture-basics-form", %{
        "lecture" => %{"title" => title, "description" => description}
      })
      |> render_submit()
    end

    test "shows enrolled students, revenue and the thumbnail image", %{conn: conn} do
      course = course_fixture(title: "Detailed Course", thumbnail_key: "cover.jpg")
      {:ok, _view, html} = live(conn, ~p"/admin/courses/#{course.slug}")

      assert html =~ "Detailed Course"
      assert html =~ "Enrolled students"
      assert html =~ "Course curriculum"
      assert html =~ "cover.jpg"
    end

    test "lecture play icon links to that lecture in course preview", %{conn: conn} do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id)
      lecture = lecture_fixture(module_id: module.id, title: "Preview me")

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      assert has_element?(
               view,
               "a[aria-label='Preview Preview me'][href='/admin/courses/#{course.slug}/preview?lecture_id=#{lecture.id}']"
             )
    end

    test "shows equal course detail tabs and switches to enrolled students", %{conn: conn} do
      course = course_fixture()
      learner = user_fixture()
      enrollment_fixture(user_id: learner.id, course_id: course.id, status: :active)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      assert has_element?(view, "#course-detail-tabs.grid.grid-cols-2")
      assert has_element?(view, "#curriculum-tab[aria-selected='true']")
      assert has_element?(view, "#curriculum-tab", "Curriculum")
      assert has_element?(view, "#students-tab[aria-selected='false']")
      assert has_element?(view, "#students-tab", "Enrolled students")
      assert has_element?(view, "#students-tab span", "1")
      assert has_element?(view, "#curriculum-panel")
      refute has_element?(view, "#students-panel")

      view |> element("#students-tab") |> render_click()

      assert has_element?(view, "#curriculum-tab[aria-selected='false']")
      assert has_element?(view, "#students-tab[aria-selected='true']")
      refute has_element?(view, "#curriculum-panel")
      assert has_element?(view, "#students-panel")
    end

    test "shows each enrolled student's completion percent and latest quiz scores", %{
      conn: conn
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
      learner = user_fixture(name: "Amina Otieno")
      enrollment_fixture(user_id: learner.id, course_id: course.id, status: :active)

      quiz = quiz_fixture(module: module, title: "Module One Quiz")
      question = question_fixture(quiz: quiz)
      correct_option = Enum.find(question.question_options, & &1.correct)

      Wasomi.Learning.record_progress(learner, lecture, lecture.duration_seconds)
      Wasomi.Assessments.submit_quiz(learner, quiz, %{question.id => correct_option.id})

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
      html = view |> render_click("switch_tab", %{"tab" => "students"})

      assert html =~ "100%"
      assert html =~ "Module One Quiz: 100%"
    end

    test "shows a dash for quiz scores and 0% progress for a student who hasn't started", %{
      conn: conn
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
      learner = user_fixture(name: "Brian Kamau")
      enrollment_fixture(user_id: learner.id, course_id: course.id, status: :active)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
      html = view |> render_click("switch_tab", %{"tab" => "students"})

      assert html =~ "Brian Kamau"
      assert html =~ "0%"
    end

    test "links each lecture to its own lecture-quiz page", %{conn: conn} do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id)
      lecture = lecture_fixture(module_id: module.id, position: 1)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      assert has_element?(
               view,
               ~s(a[href="/admin/courses/#{course.slug}/lectures/#{lecture.id}/quiz"])
             )
    end

    test "shows the number of generated lecture-quiz questions", %{conn: conn} do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id)
      lecture = lecture_fixture(module_id: module.id, position: 1)
      quiz = lecture_quiz_fixture(lecture: lecture)

      for position <- 1..2 do
        assert {:ok, _question} =
                 Wasomi.Assessments.create_lecture_quiz_question(quiz, %{
                   prompt: "Generated question #{position}",
                   status: :published,
                   position: position,
                   question_options: [
                     %{label: "Correct", correct: true, position: 1},
                     %{label: "Incorrect", correct: false, position: 2}
                   ]
                 })
      end

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      assert has_element?(view, "#lecture-#{lecture.id}", "2 quiz questions")
      refute has_element?(view, "#lecture-#{lecture.id}", "0 quiz questions")
    end

    test "shows a draft-question reminder badge only when a module has unreviewed drafts", %{
      conn: conn
    } do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      {:ok, _view, html} = live(conn, ~p"/admin/courses/#{course.slug}")

      refute html =~ "to review"

      quiz = quiz_fixture(%{module: module})
      question_fixture(%{quiz: quiz, status: :draft, position: 1})
      question_fixture(%{quiz: quiz, status: :draft, position: 2})

      {:ok, _view, html} = live(conn, ~p"/admin/courses/#{course.slug}")

      assert html =~ "2 to review"
    end

    test "edits the course from its detail page without navigating away", %{conn: conn} do
      course = course_fixture(title: "Original Title")
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      refute has_element?(view, "#course-modal")

      view |> element("button", "Edit course") |> render_click()

      assert has_element?(view, "#course-modal")

      html =
        view
        |> form("#course-form", course: %{title: "Updated Title"})
        |> render_submit()

      assert_patch(view, ~p"/admin/courses/#{course.slug}")
      refute has_element?(view, "#course-modal")
      assert html =~ "Updated Title"
    end

    test "changing the course's own slug in the detail-page modal patches to the NEW slug, not the stale one",
         %{conn: conn} do
      course = course_fixture(slug: "old-slug")
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      view |> element("button", "Edit course") |> render_click()

      html =
        view
        |> form("#course-form", course: %{slug: "new-slug"})
        |> render_submit()

      assert_patch(view, ~p"/admin/courses/new-slug")
      refute has_element?(view, "#course-modal")
      assert html =~ "Course updated successfully"
      assert Wasomi.Catalog.get_course_by_slug!("new-slug").id == course.id
    end

    test "a module's quiz appears as a row in the curriculum once one exists", %{conn: conn} do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.slug}")

      assert has_element?(view, "button", "Add module quiz")
      refute html =~ "published"

      quiz = quiz_fixture(%{module: module, title: "Module One Quiz"})
      question_fixture(%{quiz: quiz, status: :published, position: 1})
      question_fixture(%{quiz: quiz, status: :draft, position: 2})

      {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.slug}")

      assert html =~ "Module One Quiz"
      assert html =~ "1 published"
      assert html =~ "1 to review"
      refute has_element?(view, "button", "Add module quiz")
      assert has_element?(view, "a[title='Manage quiz']")
    end

    test "deleting a module's quiz removes it and its questions", %{conn: conn} do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      quiz = quiz_fixture(%{module: module, title: "Module One Quiz"})
      question_fixture(%{quiz: quiz, status: :published, position: 1})

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

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
      assert has_element?(view, "button", "Add module quiz")
      assert_raise Ecto.NoResultsError, fn -> Wasomi.Assessments.get_quiz!(quiz.id) end
    end

    test "the module-quiz generate button is disabled until every lecture has its own quiz", %{
      conn: conn
    } do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      first = lecture_fixture(module_id: module.id, position: 1)
      second = lecture_fixture(module_id: module.id, position: 2)

      {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.slug}")

      refute has_element?(view, "button", "Add module quiz")
      assert html =~ "Generate a quiz for every lecture in this module"

      quiz = lecture_quiz_fixture(lecture: first)
      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

      {:ok, 1} =
        Wasomi.Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
          draft_question_attrs()
        ])

      {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.slug}")
      refute has_element?(view, "button", "Add module quiz")
      assert html =~ "Generate a quiz for every lecture in this module"

      second_quiz = lecture_quiz_fixture(lecture: second)
      second_generation = lecture_quiz_generation_fixture(lecture_quiz: second_quiz)

      {:ok, 1} =
        Wasomi.Assessments.create_lecture_quiz_draft_questions_and_mark_ready(
          second_generation,
          [draft_question_attrs()]
        )

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
      assert has_element?(view, "button", "Add module quiz")
    end

    test "generating a module quiz server-side rejects a not-yet-ready module", %{conn: conn} do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      lecture_fixture(module_id: module.id, position: 1)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      html =
        view
        |> render_click("generate_quiz", %{"module-id" => module.id})

      assert html =~ "Generate a quiz for every lecture in this module"
      assert Wasomi.Assessments.get_quiz_for_module(module) == nil
    end

    test "cancelling the delete-quiz confirmation leaves the quiz intact", %{conn: conn} do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      quiz = quiz_fixture(%{module: module, title: "Module One Quiz"})

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      view |> element("button[title='Delete quiz']") |> render_click()
      view |> element("#delete-quiz-modal button", "Cancel") |> render_click()

      refute has_element?(view, "#delete-quiz-modal")
      assert Wasomi.Assessments.get_quiz!(quiz.id)
    end

    test "adds a module through the curriculum editor", %{conn: conn} do
      course = course_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      view |> element("button", "Add module") |> render_click()

      assert has_element?(view, "#course_module-form textarea[name='course_module[description]']")

      html =
        view
        |> form("#course_module-form",
          course_module: %{title: "Storytelling", description: "Narrative skills"}
        )
        |> render_submit()

      assert html =~ "Storytelling"
      assert [%{title: "Storytelling", position: 1}] = Wasomi.Catalog.list_modules()
    end

    test "editing a module has no position field and leaves its position untouched", %{
      conn: conn
    } do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Original", position: 2)
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      view |> element("button[title='Edit module']") |> render_click()

      refute has_element?(view, "#course_module-form input[name='course_module[position]']")

      html =
        view
        |> form("#course_module-form",
          course_module: %{title: "Updated title", description: "Narrative skills"}
        )
        |> render_submit()

      assert html =~ "Updated title"
      assert Wasomi.Catalog.get_course_module!(module.id).position == 2
    end

    test "the lecture and module modals can't be dismissed by a stray click or Escape", %{
      conn: conn
    } do
      course = course_fixture()
      module = course_module_fixture(course_id: course.id)
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      html = render_click(view, "new_module", %{})
      assert html =~ ~s(id="module-modal")
      refute html =~ "phx-click-away"
      refute html =~ "phx-window-keydown"
      refute html =~ ~s(phx-key="escape")

      render_click(view, "close_modal", %{})

      html = render_click(view, "new_lecture", %{"module-id" => to_string(module.id)})
      assert html =~ ~s(id="lecture-modal")
      refute html =~ "phx-click-away"
      refute html =~ "phx-window-keydown"
      refute html =~ ~s(phx-key="escape")
    end

    test "uploads a lecture video via Mux and deletes the lecture", %{conn: conn} do
      import Mox

      course = course_fixture()
      module = course_module_fixture(course_id: course.id, title: "Module One")
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      # Open the "add lecture" form, save the basics, then drive the Mux upload/poll flow.
      render_click(view, "new_lecture", %{"module-id" => to_string(module.id)})

      refute has_element?(view, "#lecture-basics-form input[name='lecture[position]']")

      submit_basics(view, "Opening hook", "How to start")

      expect(Wasomi.MediaProviderMock, :create_upload, fn %Wasomi.Catalog.Lecture{}, [] ->
        {:ok, %{id: "upload-123", url: "https://storage.mux.test/direct-upload"}}
      end)

      expect(Wasomi.MediaProviderMock, :upload_status, fn "upload-123" ->
        {:ok, {:ready, "signed-playback-456", 120}}
      end)

      expect(Wasomi.MediaProviderMock, :thumbnail_url, fn %Wasomi.Catalog.Lecture{}, _user ->
        {:ok, "https://image.mux.test/signed-playback-456/thumbnail.jpg?token=abc"}
      end)

      upload = element(view, "#lecture-video-upload")
      render_hook(upload, "create-upload", %{})
      render_hook(upload, "upload-complete", %{})
      html = render_hook(upload, "check-upload", %{})
      assert html =~ "https://image.mux.test/signed-playback-456/thumbnail.jpg?token=abc"

      html = view |> element("#lecture-video-form") |> render_submit()

      assert html =~ "Opening hook"
      [lecture] = Wasomi.Catalog.list_lectures()
      assert lecture.title == "Opening hook"
      assert lecture.position == 1
      assert lecture.video_provider == :cloudflare
      assert lecture.video_asset_id == "signed-playback-456"
      assert lecture.duration_seconds == 120

      html = render_click(view, "delete_lecture", %{"id" => lecture.id})
      refute html =~ "Opening hook"
      assert Wasomi.Catalog.list_lectures() == []
    end

    test "editing a lecture has no position field and leaves its position untouched", %{
      conn: conn
    } do
      import Mox

      course = course_fixture()
      module = course_module_fixture(course_id: course.id)

      lecture =
        lecture_fixture(
          module_id: module.id,
          title: "Original",
          position: 2,
          video_asset_id: "abc123"
        )

      stub(Wasomi.MediaProviderMock, :thumbnail_url, fn %Wasomi.Catalog.Lecture{}, _user ->
        {:ok, "https://image.mux.test/abc123/thumbnail.jpg?token=abc"}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      render_click(view, "edit_lecture", %{"id" => lecture.id})

      refute has_element?(view, "#lecture-basics-form input[name='lecture[position]']")

      html =
        view
        |> form("#lecture-basics-form",
          lecture: %{title: "Updated title", description: "Updated description"}
        )
        |> render_submit()

      assert html =~ "Updated title"
      assert Wasomi.Catalog.get_lecture!(lecture.id).position == 2
    end

    test "reorders modules through the curriculum editor", %{conn: conn} do
      course = course_fixture()
      first = course_module_fixture(course_id: course.id, position: 1, title: "First module")
      second = course_module_fixture(course_id: course.id, position: 2, title: "Second module")

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

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

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

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
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      render_click(view, "new_lecture", %{"module-id" => to_string(module.id)})
      submit_basics(view, "Opening hook", "How to start")
      view |> element("#lecture-video-form") |> render_submit()

      # 1. Invalid extension: .exe
      resources_exe =
        file_input(view, "#lecture-resources-form", :resources, [
          %{name: "lesson.exe", content: "fake-exe-bytes", type: "application/x-msdownload"}
        ])

      assert {:error, [[_, %{reason: :not_accepted}]]} =
               render_upload(resources_exe, "lesson.exe")

      # 2. No extension at all
      resources_no_ext =
        file_input(view, "#lecture-resources-form", :resources, [
          %{name: "lesson", content: "fake-bytes", type: "application/octet-stream"}
        ])

      assert {:error, [[_, %{reason: :not_accepted}]]} = render_upload(resources_no_ext, "lesson")

      # 3. An image. Lecture resources are PDF only: an image can't be read for
      # text by the study-guide/quiz generators and has no inline reader.
      resources_image =
        file_input(view, "#lecture-resources-form", :resources, [
          %{name: "diagram.png", content: "fake-png-bytes", type: "image/png"}
        ])

      assert {:error, [[_, %{reason: :not_accepted}]]} =
               render_upload(resources_image, "diagram.png")

      # 4. A Word document — accepted before this became PDF-only.
      resources_docx =
        file_input(view, "#lecture-resources-form", :resources, [
          %{
            name: "handout.docx",
            content: "fake-docx-bytes",
            type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
          }
        ])

      assert {:error, [[_, %{reason: :not_accepted}]]} =
               render_upload(resources_docx, "handout.docx")
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
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      render_click(view, "new_lecture", %{"module-id" => to_string(module.id)})
      submit_basics(view, "Opening hook", "How to start")
      view |> element("#lecture-video-form") |> render_submit()

      # Upload a valid PDF file
      resources_pdf =
        file_input(view, "#lecture-resources-form", :resources, [
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

    test "publishing fails with a full checklist when the course isn't ready", %{conn: conn} do
      course = course_fixture(status: :draft)
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/edit")

      html = view |> element("button", "Publish course") |> render_click()

      assert html =~ "isn&#39;t ready to publish yet"
      assert html =~ "Curriculum"
      assert html =~ "Add at least one module."
      # Every stage shows, not just failures — price/thumbnail pass on the
      # fixture's defaults.
      assert html =~ "Pricing"
      refute html =~ "Set a course price."
      assert Wasomi.Catalog.get_course!(course.id).status == :draft
    end

    test "publishing succeeds once every requirement is met", %{conn: conn} do
      course =
        course_fixture(status: :draft, price_minor: 150_000, thumbnail_key: "cover.jpg")

      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1, video_asset_id: "abc123")

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/edit")

      view |> element("button", "Publish course") |> render_click()

      assert_patched(view, ~p"/admin/courses")
      assert Wasomi.Catalog.get_course!(course.id).status == :published
    end

    test "unpublishes a published course from the edit modal", %{conn: conn} do
      course = course_fixture(status: :published)
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/edit")

      refute has_element?(view, "button", "Publish course")
      html = view |> element("button", "Unpublish") |> render_click()

      assert html =~ "no longer visible in the public catalog"
      assert Wasomi.Catalog.get_course!(course.id).status == :draft
    end

    test "archives a published course from the edit modal through the confirm dialog", %{
      conn: conn
    } do
      course = course_fixture(status: :published)
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/edit")

      view |> element("button", "Archive") |> render_click()
      assert has_element?(view, "#archive-course-modal")

      html = view |> element("#archive-course-modal button", "Archive") |> render_click()

      refute has_element?(view, "#archive-course-modal")
      assert html =~ "no longer visible in the public catalog"
      assert Wasomi.Catalog.get_course!(course.id).status == :archived
    end

    test "an archived course's edit modal has no status-transition buttons", %{conn: conn} do
      course = course_fixture(status: :archived)
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/edit")

      refute has_element?(view, "button", "Publish course")
      refute has_element?(view, "button", "Unpublish")
      refute has_element?(view, "button", "Archive")
    end

    test "archiving from the course detail page's edit modal keeps the admin on that page", %{
      conn: conn
    } do
      course = course_fixture(status: :published, title: "Detail Page Course")
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

      view |> element("button", "Edit course") |> render_click()
      view |> element("button", "Archive") |> render_click()
      view |> element("#archive-course-modal button", "Archive") |> render_click()

      assert_patch(view, ~p"/admin/courses/#{course.slug}")
      assert Wasomi.Catalog.get_course!(course.id).status == :archived
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

    test "searches students by name, email, or phone", %{conn: conn} do
      match = user_fixture(name: "Amina Otieno", email: "amina@example.com")
      other = user_fixture(name: "Brian Kamau", email: "brian@example.com")

      {:ok, view, _html} = live(conn, ~p"/admin/students")

      html =
        view
        |> form("form[phx-change=search]", %{"q" => "Amina"})
        |> render_change()

      assert html =~ match.email
      refute html =~ other.email
    end

    test "shows a no-matches message distinct from the no-students-yet state", %{conn: conn} do
      user_fixture(name: "Amina Otieno")

      {:ok, view, _html} = live(conn, ~p"/admin/students")

      html =
        view
        |> form("form[phx-change=search]", %{"q" => "nonexistent student"})
        |> render_change()

      assert html =~ "No students match"
      refute html =~ "No students have registered yet"
    end

    test "paginates the student list, 10 per page", %{conn: conn} do
      Enum.each(1..11, fn n -> user_fixture(name: "Student #{n}") end)

      {:ok, view, html} = live(conn, ~p"/admin/students")

      assert html =~ "Page 1 of 2"
      refute html =~ "Previous"
      assert html =~ "Next"

      html =
        view
        |> element(~s(a[href="/admin/students?page=2"]))
        |> render_click()

      assert html =~ "Page 2 of 2"
      assert_patched(view, ~p"/admin/students?page=2")
    end

    test "renders the payments page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/payments")
      assert html =~ "Total transactions"
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

