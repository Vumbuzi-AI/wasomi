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
end
