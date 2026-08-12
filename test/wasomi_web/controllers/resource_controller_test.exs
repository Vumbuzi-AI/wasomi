defmodule WasomiWeb.ResourceControllerTest do
  use WasomiWeb.ConnCase

  import Wasomi.CatalogFixtures

  alias Wasomi.Enrollments

  setup :register_and_log_in_user

  test "returns 403 without active enrollment", %{conn: conn} do
    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)

    resource =
      lecture_resource_fixture(
        lecture_id: lecture.id,
        kind: :link,
        url: "https://example.com/notes",
        storage_key: nil,
        byte_size: nil,
        content_type: nil
      )

    conn = get(conn, ~p"/learn/resources/#{resource.id}/download")

    assert conn.status == 403
  end

  test "redirects active learners to the resource's stored url", %{conn: conn, user: user} do
    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)

    resource =
      lecture_resource_fixture(
        lecture_id: lecture.id,
        url: "https://cdn.example.com/lectures/notes.pdf"
      )

    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    conn = get(conn, ~p"/learn/resources/#{resource.id}/download")

    assert redirected_to(conn, 302) == "https://cdn.example.com/lectures/notes.pdf"
  end

  test "an admin with ?preview=true gets redirected despite no enrollment", %{
    conn: conn,
    user: user
  } do
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    conn = log_in_user(conn, admin)

    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)

    resource =
      lecture_resource_fixture(
        lecture_id: lecture.id,
        url: "https://cdn.example.com/lectures/notes.pdf"
      )

    conn = get(conn, ~p"/learn/resources/#{resource.id}/download?preview=true")

    assert redirected_to(conn, 302) == "https://cdn.example.com/lectures/notes.pdf"
  end

  test "a non-admin adding ?preview=true themselves still gets 403", %{conn: conn} do
    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)

    resource =
      lecture_resource_fixture(
        lecture_id: lecture.id,
        url: "https://cdn.example.com/lectures/notes.pdf"
      )

    conn = get(conn, ~p"/learn/resources/#{resource.id}/download?preview=true")

    assert conn.status == 403
  end
end
