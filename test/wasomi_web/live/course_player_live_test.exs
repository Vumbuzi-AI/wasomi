defmodule WasomiWeb.CoursePlayerLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.CatalogFixtures
  import Wasomi.CertificatesFixtures
  import Wasomi.LearningFixtures

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

  test "a lecture with no video renders without a player and can be marked complete immediately",
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

    lecture_resource_fixture(lecture_id: lecture.id, name: "Slides")
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    assert {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    refute has_element?(view, "#protected-player-#{lecture.id}")
    assert has_element?(view, "#mark-lecture-complete:not([disabled])")

    view
    |> element("#mark-lecture-complete")
    |> render_click()

    assert %{status: :completed} = Learning.get_lecture_progress(user, lecture)
    refute has_element?(view, "#mark-lecture-complete")
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

    assert has_element?(view, "#lecture-resources a", "Slides")

    assert has_element?(
             view,
             "a[href='#{~p"/learn/resources/#{resource.id}/download"}']"
           )

    assert html =~ question.question
    assert has_element?(view, "#lecture-faq form[phx-submit='submit-lecture-question']")
  end

  test "a lecture with no resources or FAQ shows neither panel", %{conn: conn, user: user} do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id)
    lecture_fixture(module_id: module.id)
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    assert {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    refute has_element?(view, "#lecture-resources")
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
    assert has_element?(view, "a[href='#{~p"/courses-taken"}']", "My courses")

    assert {:ok, archived} = Wasomi.Catalog.archive_course(course)

    # "My courses" (not the public course page, which no longer exists for
    # this course) is always a valid destination regardless of status.
    assert {:ok, view, html} = live(conn, ~p"/learn/courses/#{archived.slug}")
    assert html =~ lecture.title
    assert has_element?(view, "a[href='#{~p"/courses-taken"}']", "My courses")
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

  test "mark complete explicitly completes the lecture", %{conn: conn, user: user} do
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

    render_hook(view, "video-progress", %{"lecture_id" => lecture.id, "position_seconds" => 85})
    assert has_element?(view, "#mark-lecture-complete:not([disabled])")

    view
    |> element("#mark-lecture-complete")
    |> render_click()

    assert %{status: :completed, last_position_seconds: 100} =
             Learning.get_lecture_progress(user, lecture)

    assert has_element?(view, "#course-progress-percent", "100%")
    refute has_element?(view, "#mark-lecture-complete")
  end

  test "the mark-complete button is disabled and explains why below the 80% watch threshold", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)
    lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")

    assert has_element?(view, "#mark-lecture-complete[disabled]")
    assert render(view) =~ "Watch at least 80% of this lecture to unlock this button."
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

      assert has_element?(view, "nav button.bg-white.text-primary", "Lessons")
    end

    test "the nav links Flashcards/Extra practice/Timed quiz to the study hub, pre-scoped to the current module",
         %{conn: conn, user: user} do
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: module.id, position: 1)
      {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}")
      view |> element("button[data-lecture-id='#{lecture.id}']") |> render_click()

      for {label, mode} <- [
            {"Flashcards", "flashcards"},
            {"Extra practice", "practice"},
            {"Timed quiz", "timed_quiz"}
          ] do
        assert has_element?(
                 view,
                 "nav a[href*='course=#{course.slug}'][href*='module=#{module.id}']" <>
                   "[href*='scope=module'][href*='mode=#{mode}']",
                 label
               )
      end
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

      assert has_element?(
               view,
               "nav a[href='/learn/study?course=#{course.slug}']",
               "Flashcards"
             )
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

      assert has_element?(view, "nav button.bg-white.text-primary", "Lessons")
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
        |> element("button[phx-value-module_id='#{module1.id}']")
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
      view |> element("button[phx-value-module_id='#{module1.id}']") |> render_click()
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
      first = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
      second = lecture_fixture(module_id: module.id, position: 2, duration_seconds: 100)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")

      # Unlike a real learner, an admin previewing content isn't sequentially
      # gated — the second lecture is reachable from the start.
      assert has_element?(view, "button[data-lecture-id='#{second.id}'][data-locked='false']")

      render_hook(view, "video-progress", %{"lecture_id" => first.id, "position_seconds" => 90})

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

      question =
        lecture_question_fixture(
          lecture_id: lecture.id,
          question: "Why does this matter?",
          answer: "Because it does."
        )

      assert {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.slug}/preview")

      assert has_element?(view, "#lecture-resources a", "Slides")

      assert has_element?(
               view,
               "a[href='#{~p"/learn/resources/#{resource.id}/download?preview=true"}']"
             )

      assert html =~ question.question
      assert has_element?(view, "#lecture-faq")
    end
  end
end
