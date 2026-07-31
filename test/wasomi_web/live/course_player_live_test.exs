defmodule WasomiWeb.CoursePlayerLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.CatalogFixtures
  import Wasomi.CertificatesFixtures

  alias Wasomi.{Certificates, Enrollments, Learning}

  setup :register_and_log_in_user

  test "pending learners are redirected before protected content is rendered", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id, title: "Secret paid lecture")
    {:ok, _pending} = Enrollments.create_pending_enrollment(user, course)

    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/learn/courses/#{course.slug}")
    assert path == ~p"/courses/#{course.slug}/checkout"
    refute path =~ lecture.title
  end

  test "active learners can render protected course content", %{conn: conn, user: user} do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id, title: "Unlocked lecture")
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    assert {:ok, view, html} = live(conn, ~p"/learn/courses/#{course.slug}")
    assert html =~ lecture.title
    assert html =~ user.email

    assert has_element?(
             view,
             "#protected-player-#{lecture.id}[phx-hook='ProtectedVideo'][data-playback-url]"
           )

    assert has_element?(view, "#course-progress-percent", "0%")
    assert has_element?(view, "#mark-lecture-complete")
  end

  test "time updates save progress and unlock the next lecture after completion", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)
    first = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
    second = lecture_fixture(module_id: module.id, position: 2, duration_seconds: 100)
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    assert has_element?(view, "button[data-lecture-id='#{second.id}'][data-locked='true']")

    render_hook(view, "video-progress", %{
      "lecture_id" => first.id,
      "position_seconds" => 40
    })

    assert %{status: :in_progress, last_position_seconds: 40} =
             Learning.get_lecture_progress(user, first)

    assert has_element?(view, "button[data-lecture-id='#{second.id}'][data-locked='true']")

    render_hook(view, "video-progress", %{
      "lecture_id" => first.id,
      "position_seconds" => 95
    })

    assert %{status: :completed} = Learning.get_lecture_progress(user, first)
    assert has_element?(view, "#course-progress-percent", "50%")
    assert has_element?(view, "button[data-lecture-id='#{second.id}'][data-locked='false']")

    view
    |> element("button[data-lecture-id='#{second.id}']")
    |> render_click()

    assert has_element?(view, "#protected-player-#{second.id}")
  end

  test "cannot select a locked lecture by forging a client event", %{conn: conn, user: user} do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)
    first = lecture_fixture(module_id: module.id, position: 1)
    second = lecture_fixture(module_id: module.id, position: 2)
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
    render_hook(view, "select-lecture", %{"id" => second.id})

    assert render(view) =~ "Complete the previous lecture to unlock this one."
    assert has_element?(view, "#protected-player-#{first.id}")
    refute has_element?(view, "#protected-player-#{second.id}")
  end

  test "mark complete explicitly completes the lecture", %{conn: conn, user: user} do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)
    lecture = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    view
    |> element("#mark-lecture-complete")
    |> render_click()

    assert %{status: :completed, last_position_seconds: 100} =
             Learning.get_lecture_progress(user, lecture)

    assert has_element?(view, "#course-progress-percent", "100%")
    refute has_element?(view, "#mark-lecture-complete")
  end

  test "certificate ready PubSub events reveal a download button", %{conn: conn, user: user} do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)
    lecture_fixture(module_id: module.id, position: 1)
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
    assert has_element?(view, "#course-certificates")

    certificate =
      certificate_fixture(user_id: user.id, course_id: course.id, module_id: module.id)

    :ok = Certificates.broadcast_ready(certificate)

    assert has_element?(
             view,
             "#certificate-#{certificate.id} a[href='/certificates/#{certificate.id}/download']"
           )
  end

  describe "admin preview mode" do
    defp admin_fixture(attrs \\ %{}) do
      user = Wasomi.AccountsFixtures.user_fixture(attrs)
      {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
      admin
    end

    test "non-admins cannot reach the preview route" do
      course = course_fixture(status: :published)
      conn = build_conn() |> log_in_user(Wasomi.AccountsFixtures.user_fixture())

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, ~p"/admin/courses/#{course.slug}/preview")
    end

    test "an admin can preview an unpublished course with no enrollment" do
      conn = build_conn() |> log_in_user(admin_fixture())
      course = course_fixture(status: :draft, title: "Unfinished Course")
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1, title: "Draft lecture")

      assert {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")

      assert html =~ "Unfinished Course"
      assert html =~ "Draft lecture"
      assert html =~ "Admin Preview Mode"
      assert has_element?(view, "#admin-preview-banner")
    end

    test "marking a lecture complete in preview mode does not persist progress" do
      conn = build_conn() |> log_in_user(admin_fixture())
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id, position: 1)
      _first = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
      second = lecture_fixture(module_id: module.id, position: 2, duration_seconds: 100)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")

      assert has_element?(view, "button[data-lecture-id='#{second.id}'][data-locked='true']")

      view
      |> element("#mark-lecture-complete")
      |> render_click()

      assert has_element?(view, "#course-progress-percent", "50%")
      assert has_element?(view, "button[data-lecture-id='#{second.id}'][data-locked='false']")
      assert render(view) =~ "preview only, nothing was saved"

      # Nothing was written for any user — this is the whole point of preview
      # mode, not just a check against the admin's own progress row.
      assert Wasomi.Learning.list_lecture_progress() == []
    end

    test "video-progress ticks update the watched percentage shown in preview mode" do
      conn = build_conn() |> log_in_user(admin_fixture())
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")

      render_hook(view, "video-progress", %{
        "lecture_id" => lecture.id,
        "position_seconds" => 40
      })

      assert render(view) =~ "40% watched"

      # Nothing persisted, same guarantee as the other preview-mode tests.
      assert Wasomi.Learning.list_lecture_progress() == []
    end

    test "submitting a quiz in preview mode does not persist a submission" do
      admin = admin_fixture()
      conn = build_conn() |> log_in_user(admin)
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      quiz = Wasomi.AssessmentsFixtures.quiz_fixture(%{module: module})

      question = Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz})
      correct_option = Enum.find(question.question_options, & &1.correct)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")

      view
      |> element("button", "Module 1 Quiz")
      |> render_click()

      view
      |> element(
        "input[phx-value-question-id='#{question.id}'][phx-value-option-id='#{correct_option.id}']"
      )
      |> render_click()

      html =
        view
        |> form("form[phx-submit='submit-quiz']")
        |> render_submit()

      assert html =~ "preview"
      assert Wasomi.Assessments.list_submissions_for_user(admin, quiz) == []
    end

    test "a multi-question quiz shows one question at a time with Back/Next navigation" do
      conn = build_conn() |> log_in_user(admin_fixture())
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      quiz = Wasomi.AssessmentsFixtures.quiz_fixture(%{module: module})

      first = Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz, position: 1})
      second = Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz, position: 2})

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")

      view |> element("button", "Module 1 Quiz") |> render_click()

      html = render(view)
      assert html =~ "Question 1 of 2"
      assert html =~ first.prompt
      refute html =~ second.prompt
      assert has_element?(view, "button[disabled]", "Back")
      refute has_element?(view, "button", "Submit Quiz")

      view |> element("button", "Next") |> render_click()

      html = render(view)
      assert html =~ "Question 2 of 2"
      assert html =~ second.prompt
      refute html =~ first.prompt
      refute has_element?(view, "button", "Next")
      assert has_element?(view, "button[disabled]", "Submit Quiz")

      view |> element("button", "Back") |> render_click()

      html = render(view)
      assert html =~ "Question 1 of 2"
      assert html =~ first.prompt
    end

    test "the preview route never shows a certificates section" do
      conn = build_conn() |> log_in_user(admin_fixture())
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")
      refute has_element?(view, "#course-certificates")
    end
  end
end
