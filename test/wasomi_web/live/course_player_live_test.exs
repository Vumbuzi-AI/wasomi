defmodule WasomiWeb.CoursePlayerLiveTest do
  use WasomiWeb.ConnCase
  use Oban.Testing, repo: Wasomi.Repo

  import Phoenix.LiveViewTest
  import Wasomi.CatalogFixtures
  import Wasomi.CertificatesFixtures
  import Wasomi.LearningFixtures

  alias Wasomi.{Certificates, Enrollments, Learning, Reviews}

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
    assert html =~ course.title

    # Immersive shell: a plain exit link, no learner sidebar.
    assert has_element?(view, "a[aria-label='Exit course']")
    refute has_element?(view, "#student-sidebar")

    assert has_element?(
             view,
             "#protected-player-#{lecture.id}[phx-hook='ProtectedVideo'][data-playback-url][data-preview='false']"
           )

    assert has_element?(view, "#course-progress-percent", "0%")
    # A recording completes itself, so there is no button here — only the
    # watch-progress readout that stands in for one.
    refute has_element?(view, "#mark-lesson-complete")
    assert has_element?(view, "#lecture-watch-progress")
  end

  test "active learners can render granted draft internal course content", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :draft, is_internal: true, title: "Internal Pilot")
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id, title: "Internal pilot lecture")
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    assert {:ok, _view, html} = live(conn, ~p"/learn/courses/#{course.slug}")
    assert html =~ course.title
    assert html =~ lecture.title
  end

  test "a reading-only lecture is completed by marking its PDFs as read, with no video player",
       %{conn: conn, user: user} do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)

    lecture =
      lecture_fixture(
        module_id: module.id,
        position: 1,
        duration_seconds: nil,
        video_asset_id: nil,
        video_provider: nil
      )

    _resource = lecture_resource_fixture(lecture_id: lecture.id, name: "Slides")
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    assert {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    refute has_element?(view, "#protected-player-#{lecture.id}")
    # One completion control for the whole lesson, at the end of its body.
    assert has_element?(view, "#mark-lesson-complete")

    view
    |> element("#mark-lesson-complete")
    |> render_click()

    assert %{status: :completed} = Learning.get_lecture_progress(user, lecture)
    refute has_element?(view, "#mark-lesson-complete")
    assert render(view) =~ "Lesson complete"
  end

  test "a lecture with neither a video nor a PDF keeps the manual mark-complete button",
       %{conn: conn, user: user} do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)

    lecture =
      lecture_fixture(
        module_id: module.id,
        position: 1,
        duration_seconds: nil,
        video_asset_id: nil,
        video_provider: nil
      )

    lecture_resource_fixture(
      lecture_id: lecture.id,
      kind: :link,
      name: "Reference",
      url: "https://example.com/reference",
      storage_key: nil,
      byte_size: nil,
      content_type: nil
    )

    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    assert {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    assert has_element?(view, "#mark-lesson-complete")

    view
    |> element("#mark-lesson-complete")
    |> render_click()

    assert %{status: :completed} = Learning.get_lecture_progress(user, lecture)
    refute has_element?(view, "#mark-lesson-complete")
  end

  test "resources and FAQ for the current lecture are rendered to enrolled learners", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)

    resource =
      lecture_resource_fixture(
        lecture_id: lecture.id,
        kind: :link,
        name: "Slides",
        url: "https://example.com/slides",
        storage_key: nil,
        byte_size: nil,
        content_type: nil
      )

    question =
      lecture_question_fixture(
        lecture_id: lecture.id,
        question: "Why does this matter?",
        answer: "Because it does."
      )

    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    assert {:ok, view, html} = live(conn, ~p"/learn/courses/#{course.slug}")

    assert has_element?(view, "#resources-panel a", "Slides")

    assert has_element?(
             view,
             "a[href='#{~p"/learn/resources/#{resource.id}/download"}']"
           )

    assert html =~ question.question
    assert has_element?(view, "#lecture-faq form[phx-submit='submit-lecture-question']")
  end

  test "PDF resources are displayed inline for enrolled learners", %{conn: conn, user: user} do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)

    resource =
      lecture_resource_fixture(
        lecture_id: lecture.id,
        kind: :document,
        name: "Firewall assignment.pdf",
        content_type: "application/pdf"
      )

    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
    resource_path = ~p"/learn/resources/#{resource.id}/download"

    assert has_element?(
             view,
             "#lesson-pdfs #pdf-deck-#{resource.id}[phx-hook='PdfDeck'][data-src='#{resource_path}']"
           )
  end

  test "a lecture with no resources or FAQ shows neither panel", %{conn: conn, user: user} do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id)
    lecture_fixture(module_id: module.id)
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    assert {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    refute has_element?(view, "#lecture-faq")
  end

  test "an already-enrolled learner keeps access after the course is archived", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id, title: "Still-watchable lecture")
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    assert {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
    assert has_element?(view, "a[href='#{~p"/courses-taken"}'][aria-label='Exit course']")

    assert {:ok, archived} = Wasomi.Catalog.archive_course(course)

    # "My courses" (not the public course page, which no longer exists for
    # this course) is always a valid destination regardless of status.
    assert {:ok, view, html} = live(conn, ~p"/learn/courses/#{archived.slug}")
    assert html =~ lecture.title
    assert has_element?(view, "a[href='#{~p"/courses-taken"}'][aria-label='Exit course']")
  end

  test "a non-enrolled visitor to an archived course is redirected to the catalog, not checkout",
       %{conn: conn} do
    course = course_fixture(status: :published)
    assert {:ok, archived} = Wasomi.Catalog.archive_course(course)

    assert {:error, {:redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/learn/courses/#{archived.slug}")

    assert path == ~p"/courses"
    assert flash["error"] == "This course isn't available."
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
      "position_seconds" => 15
    })

    assert %{status: :in_progress, last_position_seconds: 15} =
             Learning.get_lecture_progress(user, first)

    assert has_element?(view, "button[data-lecture-id='#{second.id}'][data-locked='true']")

    # Backdate so the plausibility clamp accepts this jump as real watch time.
    progress = Learning.get_lecture_progress(user, first)

    Wasomi.Repo.update!(
      Ecto.Changeset.change(progress,
        updated_at: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
      )
    )

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

  test "a watched video completes itself without any button press", %{conn: conn, user: user} do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)
    lecture = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    render_hook(view, "video-progress", %{"lecture_id" => lecture.id, "position_seconds" => 15})

    # Backdate so the plausibility clamp accepts this jump as real watch time.
    Wasomi.Repo.update!(
      Ecto.Changeset.change(Learning.get_lecture_progress(user, lecture),
        updated_at: DateTime.utc_now() |> DateTime.add(-30, :second) |> DateTime.truncate(:second)
      )
    )

    # 85% is past the mark-complete threshold but short of the 95% auto-complete
    # mark: still in progress, and still no button offered.
    render_hook(view, "video-progress", %{"lecture_id" => lecture.id, "position_seconds" => 85})
    assert %{status: :in_progress} = Learning.get_lecture_progress(user, lecture)
    refute has_element?(view, "#mark-lesson-complete")
    assert has_element?(view, "#lecture-watch-progress")

    Wasomi.Repo.update!(
      Ecto.Changeset.change(Learning.get_lecture_progress(user, lecture),
        updated_at: DateTime.utc_now() |> DateTime.add(-30, :second) |> DateTime.truncate(:second)
      )
    )

    render_hook(view, "video-progress", %{"lecture_id" => lecture.id, "position_seconds" => 100})

    assert %{status: :completed, last_position_seconds: 100} =
             Learning.get_lecture_progress(user, lecture)

    assert has_element?(view, "#course-progress-percent", "100%")
    refute has_element?(view, "#lecture-watch-progress")
  end

  test "a video lesson shows a watch-progress readout rather than a manual complete button", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)
    lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    refute has_element?(view, "#mark-lesson-complete")
    assert has_element?(view, "#lecture-watch-progress", "% watched")
  end

  test "cannot mark a lecture complete below the watch threshold by forging a client event", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)
    lecture = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
    render_hook(view, "complete-lecture", %{"lecture_id" => to_string(lecture.id)})

    assert render(view) =~ "Watch more of this lecture before marking it complete."
    refute match?(%{status: :completed}, Learning.get_lecture_progress(user, lecture))
  end

  describe "certificate celebration modal" do
    setup %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
      %{view: view, course: course}
    end

    test "pops with download, LinkedIn, and a preview image when the current course's certificate is ready",
         %{view: view, course: course, user: user} do
      certificate = certificate_fixture(user_id: user.id, course_id: course.id)
      :ok = Certificates.broadcast_ready(certificate)

      assert has_element?(view, "#certificate-celebration")
      assert has_element?(view, "#certificate-celebration", course.title)

      assert has_element?(
               view,
               "a[href='/certificates/#{certificate.id}/download']",
               "Download certificate"
             )

      assert has_element?(view, "a[href^='https://www.linkedin.com/profile/add']")

      html = render(view)
      assert html =~ ~s(src="/certificates/#{certificate.id}/preview")
      assert html =~ "onerror"
    end

    test "does not pop for a certificate from a different course", %{view: view, user: user} do
      other_course = course_fixture(status: :published)
      certificate = certificate_fixture(user_id: user.id, course_id: other_course.id)
      :ok = Certificates.broadcast_ready(certificate)

      refute has_element?(view, "#certificate-celebration")
    end

    test "dismissing removes the modal", %{view: view, course: course, user: user} do
      certificate = certificate_fixture(user_id: user.id, course_id: course.id)
      :ok = Certificates.broadcast_ready(certificate)
      assert has_element?(view, "#certificate-celebration")

      view
      |> element("#certificate-celebration button[aria-label='Close']")
      |> render_click()

      refute has_element?(view, "#certificate-celebration")
    end
  end

  test "a module quiz is locked in the sidebar until every lecture in that module is completed",
       %{conn: conn, user: user} do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)
    first = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
    second = lecture_fixture(module_id: module.id, position: 2, duration_seconds: 100)
    quiz = Wasomi.AssessmentsFixtures.quiz_fixture(%{module: module})
    Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz})
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    assert has_element?(view, "button[disabled][data-locked='true']", "Module 1 Quiz")

    {:ok, _progress, _events} = complete_lecture_via_progress!(user, first)
    {:ok, _progress, _events} = complete_lecture_via_progress!(user, second)

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    refute has_element?(view, "button[disabled]", "Module 1 Quiz")
    assert has_element?(view, "button[data-locked='false']", "Module 1 Quiz")

    view |> element("button", "Module 1 Quiz") |> render_click()
    assert render(view) =~ "Question 1 of 1"
  end

  test "a quiz on a module with zero lectures stays locked, not vacuously unlocked", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published)
    populated_module = course_module_fixture(course_id: course.id, position: 1)
    lecture_fixture(module_id: populated_module.id, position: 1)
    empty_module = course_module_fixture(course_id: course.id, position: 2)
    quiz = Wasomi.AssessmentsFixtures.quiz_fixture(%{module: empty_module})
    Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz})
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    assert has_element?(view, "button[disabled][data-locked='true']", "Module 2 Quiz")
  end

  test "cannot select a locked module quiz by forging a client event", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)
    lecture_fixture(module_id: module.id, position: 1)
    quiz = Wasomi.AssessmentsFixtures.quiz_fixture(%{module: module})
    Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz})
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
    render_hook(view, "select-quiz", %{"module_id" => to_string(module.id)})

    assert render(view) =~ "Complete this module&#39;s lectures to unlock its quiz."
    refute render(view) =~ "Question 1 of"
  end

  test "reopening a quiz with an existing real submission does not crash the LiveView", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)
    lecture = lecture_fixture(module_id: module.id, position: 1)
    quiz = Wasomi.AssessmentsFixtures.quiz_fixture(%{module: module})
    question = Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz})
    correct_option = Enum.find(question.question_options, & &1.correct)
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)
    {:ok, _progress, _events} = complete_lecture_via_progress!(user, lecture)

    {:ok, submission} =
      Wasomi.Assessments.submit_quiz(user, quiz, %{
        to_string(question.id) => to_string(correct_option.id)
      })

    assert %Wasomi.Assessments.QuizSubmission{} = submission

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    html =
      view
      |> element("button", "Module 1 Quiz")
      |> render_click()

    assert html =~ "#{submission.score_percent}%"
    refute html =~ "Admin Preview Result"
  end

  describe "capture protection" do
    setup %{user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id)
      lecture = lecture_fixture(module_id: module.id)
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)

      %{course: course, lecture: lecture}
    end

    test "the workspace is watermarked with the viewer's identity and guarded client-side", %{
      conn: conn,
      user: user,
      course: course,
      lecture: lecture
    } do
      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
      stamp = "User ##{user.id}"

      # The page-wide guard (shortcut blocking + tiled watermark overlay) and
      # the in-frame video stamp both need the identity, so both carry it: a
      # capture cropped to just the video is still attributable.
      assert has_element?(
               view,
               "#course-player[phx-hook='CaptureGuard'][data-watermark='#{stamp}']"
             )

      assert has_element?(
               view,
               "#protected-player-#{lecture.id}[data-watermark='#{stamp}']"
             )

      assert has_element?(view, "[data-role='watermark']", stamp)
      refute has_element?(view, "[data-watermark*='#{user.email}']")
    end

    test "a reported capture attempt is logged and never breaks playback", %{
      conn: conn,
      user: user,
      course: course
    } do
      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert render_hook(view, "capture-attempt", %{"kind" => "printscreen"})
        end)

      assert log =~ "capture attempt: kind=printscreen user_id=#{user.id}"
      assert log =~ "course=#{course.slug}"
    end

    test "an unrecognised capture kind is ignored rather than logged", %{
      conn: conn,
      course: course
    } do
      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert render_hook(view, "capture-attempt", %{"kind" => "not-a-real-kind"})
        end)

      refute log =~ "capture attempt"
    end
  end

  describe "section nav and the Module quiz panel" do
    test "the nav renders Lessons and Module quiz tabs, active by default on Lessons", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

      for label <- ["Lessons", "Module quiz"] do
        assert has_element?(view, "nav button", label)
      end

      assert has_element?(view, "nav button.bg-dark.text-white", "Lessons")
    end

    test "the study tools stay in the course workspace and Flashcards opens at the scope picker",
         %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1)
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
      view |> element("button[data-lecture-id='#{lecture.id}']") |> render_click()

      view |> element("button[phx-value-tool='flashcards']") |> render_click()

      assert has_element?(view, "#embedded-study-tool-flashcards-lesson")
    end

    test "Smart Test stays in the course workspace and opens at the scope picker", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1)
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
      view |> element("button[data-lecture-id='#{lecture.id}']") |> render_click()
      view |> element("button[phx-value-tool='timed_quiz']") |> render_click()

      assert has_element?(view, "#embedded-study-tool-timed_quiz-lesson")
      refute has_element?(view, "iframe")

      smart_test = find_live_child(view, "embedded-study-tool-timed_quiz-lesson")
      assert has_element?(smart_test, "h2", "Study the whole module, or one lesson?")

      smart_test |> element("button[phx-value-scope='module']") |> render_click()
      assert has_element?(smart_test, "button", "Create test")
    end

    test "the nav falls back to the study hub's own picker when no lecture is selected", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      course_module_fixture(course_id: course.id, position: 1)
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

      view |> element("button[phx-value-tool='flashcards']") |> render_click()

      assert has_element?(view, "#embedded-study-tool-flashcards-lesson")
    end

    test "an unknown section value is ignored rather than crashing the view", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
      render_hook(view, "select-section", %{"section" => "not_a_real_section"})

      assert has_element?(view, "nav button.bg-dark.text-white", "Lessons")
    end

    test "a multi-module course shows a module picker for the Module quiz section", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module1 = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module1.id, position: 1)
      module2 = course_module_fixture(course_id: course.id, position: 2)
      lecture_fixture(module_id: module2.id, position: 1)
      quiz = Wasomi.AssessmentsFixtures.quiz_fixture(%{module: module1})
      Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz})
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
      html = view |> element("nav button", "Module quiz") |> render_click()

      assert html =~ "Choose a module to take its quiz"
      assert html =~ "No quiz available yet"
      refute html =~ "Question 1 of"
    end

    test "picking an unlocked module from the picker shows that module's quiz", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module1 = course_module_fixture(course_id: course.id, position: 1)
      lecture1 = lecture_fixture(module_id: module1.id, position: 1)
      module2 = course_module_fixture(course_id: course.id, position: 2)
      lecture_fixture(module_id: module2.id, position: 1)
      quiz = Wasomi.AssessmentsFixtures.quiz_fixture(%{module: module1})
      Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz})
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)
      {:ok, _progress, _events} = complete_lecture_via_progress!(user, lecture1)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
      view |> element("nav button", "Module quiz") |> render_click()

      html =
        view
        |> element("#module-quiz-picker button[phx-value-module_id='#{module1.id}']")
        |> render_click()

      assert html =~ "Question 1 of 1"
      assert has_element?(view, "button", "Choose a different module")
    end

    test "exit-quiz returns to the module picker", %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module1 = course_module_fixture(course_id: course.id, position: 1)
      lecture1 = lecture_fixture(module_id: module1.id, position: 1)
      module2 = course_module_fixture(course_id: course.id, position: 2)
      lecture_fixture(module_id: module2.id, position: 1)
      quiz = Wasomi.AssessmentsFixtures.quiz_fixture(%{module: module1})
      Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz})
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)
      {:ok, _progress, _events} = complete_lecture_via_progress!(user, lecture1)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
      view |> element("nav button", "Module quiz") |> render_click()

      view
      |> element("#module-quiz-picker button[phx-value-module_id='#{module1.id}']")
      |> render_click()

      assert has_element?(view, "form[phx-submit='submit-quiz']")

      html = view |> element("button", "Choose a different module") |> render_click()

      assert html =~ "Choose a module to take its quiz"
      refute has_element?(view, "form[phx-submit='submit-quiz']")
    end

    test "a single-module course skips the picker and shows the quiz directly", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1)
      quiz = Wasomi.AssessmentsFixtures.quiz_fixture(%{module: module})
      Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz})
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)
      {:ok, _progress, _events} = complete_lecture_via_progress!(user, lecture)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
      html = view |> element("nav button", "Module quiz") |> render_click()

      assert html =~ "Question 1 of 1"
      refute html =~ "Choose a module to take its quiz"
      # A single-module course has nothing to pick, so the "change module"
      # escape hatch would be pointless — it's hidden rather than shown-disabled.
      refute html =~ "Choose a different module"
    end

    test "the Lessons two-column layout still renders after switching sections and back", %{
      conn: conn,
      user: user
    } do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1)
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
      view |> element("nav button", "Module quiz") |> render_click()
      html = view |> element("nav button", "Lessons") |> render_click()

      assert html =~ lecture.title
      assert has_element?(view, "#protected-player-#{lecture.id}")
    end
  end

  describe "lesson quiz" do
    setup %{user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)

      first =
        lecture_fixture(
          module_id: module.id,
          position: 1,
          duration_seconds: nil,
          video_asset_id: nil,
          video_provider: nil
        )

      second = lecture_fixture(module_id: module.id, position: 2)
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)

      %{course: course, first: first, second: second}
    end

    test "a lecture with no quiz renders no lesson-quiz panel", %{conn: conn, course: course} do
      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

      refute has_element?(view, "#lesson-quiz")
    end

    test "a quiz with only draft questions is not shown to the learner", %{
      conn: conn,
      course: course,
      first: first
    } do
      lecture_quiz_with_question(first, :draft)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

      refute has_element?(view, "#lesson-quiz")
    end

    test "published questions render inline, and passing unlocks the next lesson", %{
      conn: conn,
      user: user,
      course: course,
      first: first,
      second: second
    } do
      {quiz, question} = lecture_quiz_with_question(first, :published)
      correct = Enum.find(question.question_options, & &1.correct)

      {:ok, view, html} = live(conn, ~p"/learn/courses/#{course.slug}")

      assert has_element?(view, "#lesson-quiz")
      assert html =~ question.prompt
      assert html =~ correct.label

      # The outline flags the lesson as owing a quiz.
      assert has_element?(view, "button[data-lecture-id='#{first.id}']", "Quiz to pass")

      view |> element("#mark-lesson-complete") |> render_click()

      # Completing the lecture is no longer enough on its own.
      assert has_element?(view, "button[data-lecture-id='#{second.id}'][data-locked='true']")

      view
      |> element("#lesson-quiz input[value='#{correct.id}']")
      |> render_click()

      view |> element("#lesson-quiz form") |> render_submit()

      assert Wasomi.Assessments.passed_lecture_quiz?(user, quiz)
      assert render(view) =~ "You scored 100%"
      assert has_element?(view, "button[data-lecture-id='#{second.id}'][data-locked='false']")
      assert has_element?(view, "button[data-lecture-id='#{first.id}']", "Quiz passed")
    end

    test "failing the quiz keeps the next lesson locked and offers a retake", %{
      conn: conn,
      course: course,
      first: first,
      second: second
    } do
      {_quiz, question} = lecture_quiz_with_question(first, :published)
      wrong = Enum.find(question.question_options, &(not &1.correct))

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

      view |> element("#mark-lesson-complete") |> render_click()
      view |> element("#lesson-quiz input[value='#{wrong.id}']") |> render_click()
      view |> element("#lesson-quiz form") |> render_submit()

      assert render(view) =~ "You scored 0%"
      assert has_element?(view, "button[data-lecture-id='#{second.id}'][data-locked='true']")

      view |> element("#lesson-quiz button", "Retake quiz") |> render_click()

      assert has_element?(view, "#lesson-quiz form")
    end

    defp lecture_quiz_with_question(lecture, status) do
      quiz = Wasomi.AssessmentsFixtures.lecture_quiz_fixture(lecture: lecture)

      {:ok, question} =
        Wasomi.Assessments.create_lecture_quiz_question(quiz, %{
          prompt: "What does this lesson cover?",
          status: status,
          position: 1,
          question_options: [
            %{label: "The right answer", correct: true, position: 1},
            %{label: "The wrong answer", correct: false, position: 2}
          ]
        })

      {quiz, Wasomi.Repo.preload(question, :question_options)}
    end
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

      assert {:error, {:redirect, %{to: "/dashboard"}}} =
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
      assert has_element?(view, "[phx-hook='ProtectedVideo'][data-preview='true']")
    end

    test "an admin can open preview on a requested lecture" do
      conn = build_conn() |> log_in_user(admin_fixture())
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id, position: 1)
      first = lecture_fixture(module_id: module.id, position: 1, title: "First lecture")
      second = lecture_fixture(module_id: module.id, position: 2, title: "Selected lecture")

      {:ok, view, _html} =
        live(conn, ~p"/admin/courses/#{course.slug}/preview?#{%{lecture_id: second.id}}")

      assert has_element?(view, "#protected-player-#{second.id}")
      refute has_element?(view, "#protected-player-#{first.id}")
    end

    test "completing a lecture in preview mode does not persist progress" do
      conn = build_conn() |> log_in_user(admin_fixture())
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id, position: 1)
      first = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
      second = lecture_fixture(module_id: module.id, position: 2, duration_seconds: 100)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")

      # Unlike a real learner, an admin previewing content isn't sequentially
      # gated — the second lecture is reachable from the start.
      assert has_element?(view, "button[data-lecture-id='#{second.id}'][data-locked='false']")

      # Same auto-complete rule as a real learner's: watching past 95% is what
      # completes the lecture, here as there. There is no button to click.
      render_hook(view, "video-progress", %{"lecture_id" => first.id, "position_seconds" => 100})

      assert has_element?(view, "#course-progress-percent", "50%")
      assert has_element?(view, "button[data-lecture-id='#{second.id}'][data-locked='false']")

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

    test "an admin can jump straight to a later, not-yet-completed lecture in preview mode" do
      conn = build_conn() |> log_in_user(admin_fixture())
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1, title: "First lecture")
      second = lecture_fixture(module_id: module.id, position: 2, title: "Second lecture")

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")

      html = view |> element("button[data-lecture-id='#{second.id}']") |> render_click()

      assert html =~ "Second lecture"
      refute html =~ "Complete the previous lecture"
    end

    test "an admin can reach a module quiz in preview mode without completing any lectures" do
      conn = build_conn() |> log_in_user(admin_fixture())
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: module.id, position: 1)
      quiz = Wasomi.AssessmentsFixtures.quiz_fixture(%{module: module})
      Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz})

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")

      html = view |> element("button", "Module 1 Quiz") |> render_click()

      assert html =~ "Question 1 of 1"
      refute html =~ "Complete this module&#39;s lectures"
    end

    test "submitting a quiz in preview mode does not persist a submission" do
      admin = admin_fixture()
      conn = build_conn() |> log_in_user(admin)
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1)
      quiz = Wasomi.AssessmentsFixtures.quiz_fixture(%{module: module})

      question = Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz})
      correct_option = Enum.find(question.question_options, & &1.correct)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")

      render_hook(view, "video-progress", %{"lecture_id" => lecture.id, "position_seconds" => 40})
      render_hook(view, "complete-lecture", %{"lecture_id" => lecture.id})

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
      lecture = lecture_fixture(module_id: module.id, position: 1)
      quiz = Wasomi.AssessmentsFixtures.quiz_fixture(%{module: module})

      first = Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz, position: 1})
      second = Wasomi.AssessmentsFixtures.question_fixture(%{quiz: quiz, position: 2})

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")

      render_hook(view, "video-progress", %{"lecture_id" => lecture.id, "position_seconds" => 40})
      render_hook(view, "complete-lecture", %{"lecture_id" => lecture.id})
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

    test "resources and FAQ render identically in preview mode" do
      conn = build_conn() |> log_in_user(admin_fixture())
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1)

      resource =
        lecture_resource_fixture(
          lecture_id: lecture.id,
          kind: :link,
          name: "Slides",
          url: "https://example.com/slides",
          storage_key: nil,
          byte_size: nil,
          content_type: nil
        )

      pdf_resource =
        lecture_resource_fixture(
          lecture_id: lecture.id,
          position: 2,
          kind: :document,
          name: "Preview notes.pdf",
          content_type: "application/pdf"
        )

      question =
        lecture_question_fixture(
          lecture_id: lecture.id,
          question: "Why does this matter?",
          answer: "Because it does."
        )

      assert {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")

      assert has_element?(view, "#resources-panel a", "Slides")
      resource_path = ~p"/learn/resources/#{resource.id}/download?preview=true"
      pdf_resource_path = ~p"/learn/resources/#{pdf_resource.id}/download?preview=true"

      assert has_element?(
               view,
               "a[href='#{resource_path}']"
             )

      assert has_element?(
               view,
               "#lesson-pdfs #pdf-deck-#{pdf_resource.id}[phx-hook='PdfDeck'][data-src='#{pdf_resource_path}']"
             )

      assert html =~ question.question
      assert has_element?(view, "#lecture-faq")
    end
  end

  describe "course rating inline section" do
    setup %{user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)

      first =
        lecture_fixture(
          module_id: module.id,
          position: 1,
          duration_seconds: nil,
          video_asset_id: nil,
          video_provider: nil
        )

      last =
        lecture_fixture(
          module_id: module.id,
          position: 2,
          duration_seconds: nil,
          video_asset_id: nil,
          video_provider: nil
        )

      last_pdf =
        lecture_resource_fixture(
          lecture_id: last.id,
          kind: :document,
          name: "Final lesson notes.pdf",
          content_type: "application/pdf"
        )

      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)

      %{course: course, first: first, last: last, last_pdf: last_pdf, user: user}
    end

    test "does not appear on non-final lectures or incomplete final lectures", %{
      conn: conn,
      course: course,
      first: first
    } do
      assert {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

      # On first (non-final) lecture
      refute has_element?(view, "#course-rating-section")

      # Navigate to last lecture before it is completed
      assert {:ok, view, _html} =
               live(conn, ~p"/learn/courses/#{course.slug}?lecture_id=#{first.id}")

      refute has_element?(view, "#course-rating-section")
    end

    test "appears on the final lecture once completed, allowing star rating and comment submission",
         %{conn: conn, course: course, first: first, last: last, last_pdf: last_pdf, user: user} do
      certificate = certificate_fixture(user_id: user.id, course_id: course.id)
      # Complete first lecture
      {:ok, _progress, _} = Learning.mark_complete(user, first)

      assert {:ok, view, _html} =
               live(conn, ~p"/learn/courses/#{course.slug}?lecture_id=#{last.id}")

      refute has_element?(view, "#course-rating-section")
      assert has_element?(view, "#pdf-deck-#{last_pdf.id}")

      # Mark final lecture complete
      view
      |> element("#mark-lesson-complete")
      |> render_click()

      # Now rating section appears inline where the PDF deck was.
      assert has_element?(view, "#course-rating-section")
      refute has_element?(view, "#pdf-deck-#{last_pdf.id}")
      assert has_element?(view, "#course-review-form")
      assert has_element?(view, "#submit-course-rating[disabled]")

      # Click 5-star rating
      view
      |> element("#rate-star-5")
      |> render_click()

      refute has_element?(view, "#submit-course-rating[disabled]")

      # Submit review with comment
      view
      |> element("#course-review-form")
      |> render_submit(%{"body" => "Great instructor and practical content!"})

      # Review is saved in the database
      assert %{rating: 5, body: "Great instructor and practical content!"} =
               Reviews.get_user_course_review(user, course)

      # Rating section now reflects submitted feedback
      assert has_element?(view, "#course-rating-section", "5/5 stars")

      assert has_element?(
               view,
               "#course-rating-section",
               "Great instructor and practical content!"
             )

      # Certificate celebration modal pops after rating submission
      assert has_element?(view, "#certificate-celebration")
      assert has_element?(view, "a[href='/certificates/#{certificate.id}/download']")
    end

    test "with no certificate yet, submitting the rating enqueues issuance and shows a preparing state",
         %{conn: conn, course: course, first: first, last: last, user: user} do
      {:ok, _progress, _} = Learning.mark_complete(user, first)

      assert {:ok, view, _html} =
               live(conn, ~p"/learn/courses/#{course.slug}?lecture_id=#{last.id}")

      view |> element("#mark-lesson-complete") |> render_click()
      view |> element("#rate-star-4") |> render_click()
      view |> element("#course-review-form") |> render_submit()

      # No cert row, nothing stashed: a job is guaranteed in flight and the
      # learner sees a "preparing" state rather than a dead end.
      assert_enqueued(
        worker: Wasomi.Certificates.Workers.IssueCertificate,
        args: %{"user_id" => user.id, "course_id" => course.id}
      )

      assert has_element?(view, "#certificate-preparing")
      assert has_element?(view, "#certificate-preparing a[href='/certificates']")
      refute has_element?(view, "#certificate-celebration")

      # When the job finishes, the broadcast upgrades it to the celebration.
      certificate = certificate_fixture(user_id: user.id, course_id: course.id)
      Certificates.broadcast_ready(certificate)

      assert has_element?(view, "#certificate-celebration")
      refute has_element?(view, "#certificate-preparing")
    end

    test "a certificate that lands before the rating is stashed and pops the instant it's submitted",
         %{conn: conn, course: course, first: first, last: last, user: user} do
      {:ok, _progress, _} = Learning.mark_complete(user, first)

      assert {:ok, view, _html} =
               live(conn, ~p"/learn/courses/#{course.slug}?lecture_id=#{last.id}")

      view |> element("#mark-lesson-complete") |> render_click()

      # Certificate finishes while the learner is still on the rating form.
      certificate = certificate_fixture(user_id: user.id, course_id: course.id)
      Certificates.broadcast_ready(certificate)

      # Held — not shown yet.
      refute has_element?(view, "#certificate-celebration")
      assert has_element?(view, "#course-rating-section")

      view |> element("#rate-star-5") |> render_click()
      view |> element("#course-review-form") |> render_submit()

      # Pops immediately from the stash, no poll.
      assert has_element?(view, "#certificate-celebration")
    end

    test "a completed-but-unrated course keeps a nudge to the rating on other lectures",
         %{conn: conn, course: course, first: first, last: last, user: user} do
      {:ok, _progress, _} = Learning.mark_complete(user, first)
      {:ok, _progress, _} = Learning.mark_complete(user, last)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

      # Mount lands on the final lecture, so the rating is visible.
      assert has_element?(view, "#course-rating-section")

      # Navigating to an earlier lecture hides the inline form — the nudge
      # keeps a one-click way back to it.
      view |> element("button[phx-value-id='#{first.id}']") |> render_click()
      refute has_element?(view, "#course-rating-section")

      assert view
             |> element("button", "rate it to get your certificate")
             |> render_click() =~ "Rate this course"
    end

    test "rating is required with no skip option on the final lecture",
         %{conn: conn, course: course, first: first, last: last, user: user} do
      _certificate = certificate_fixture(user_id: user.id, course_id: course.id)
      {:ok, _progress, _} = Learning.mark_complete(user, first)

      assert {:ok, view, _html} =
               live(conn, ~p"/learn/courses/#{course.slug}?lecture_id=#{last.id}")

      view
      |> element("#mark-lesson-complete")
      |> render_click()

      assert has_element?(view, "#course-rating-section")
      refute has_element?(view, "#skip-course-rating")
      refute has_element?(view, "#certificate-celebration")
      assert has_element?(view, "#submit-course-rating[disabled]")
    end
  end
end
