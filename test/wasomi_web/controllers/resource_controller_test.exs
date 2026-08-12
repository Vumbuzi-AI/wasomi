defmodule WasomiWeb.ResourceControllerTest do
  use WasomiWeb.ConnCase

  import Ecto.Query
  import Wasomi.CatalogFixtures

  alias Wasomi.Catalog.LectureResource
  alias Wasomi.Enrollments
  alias Wasomi.Repo

  setup :register_and_log_in_user

  setup do
    previous = Application.get_env(:wasomi, :r2_public_url)
    on_exit(fn -> Application.put_env(:wasomi, :r2_public_url, previous) end)
    Application.put_env(:wasomi, :r2_public_url, "https://cdn.example.test")
    :ok
  end

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

  test "redirects active learners to a URL recomputed from the resource's storage_key", %{
    conn: conn,
    user: user
  } do
    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)
    resource = lecture_resource_fixture(lecture_id: lecture.id, storage_key: "lectures/notes.pdf")

    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    conn = get(conn, ~p"/learn/resources/#{resource.id}/download")

    assert redirected_to(conn, 302) == "https://cdn.example.test/lectures/notes.pdf"
  end

  test "redirects active learners to a link resource's own url", %{conn: conn, user: user} do
    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)

    resource =
      lecture_resource_fixture(
        lecture_id: lecture.id,
        kind: :link,
        url: "https://example.com/reading",
        storage_key: nil,
        byte_size: nil,
        content_type: nil
      )

    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    conn = get(conn, ~p"/learn/resources/#{resource.id}/download")

    assert redirected_to(conn, 302) == "https://example.com/reading"
  end

  test "returns 404 instead of crashing when R2 isn't configured", %{conn: conn, user: user} do
    Application.delete_env(:wasomi, :r2_public_url)

    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)
    resource = lecture_resource_fixture(lecture_id: lecture.id, storage_key: "lectures/notes.pdf")

    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    conn = get(conn, ~p"/learn/resources/#{resource.id}/download")

    assert conn.status == 404
  end

  test "refuses to redirect a link resource whose stored url isn't http/https", %{
    conn: conn,
    user: user
  } do
    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)

    resource =
      lecture_resource_fixture(
        lecture_id: lecture.id,
        kind: :link,
        url: "https://example.com/reading",
        storage_key: nil,
        byte_size: nil,
        content_type: nil
      )

    # A changeset can never persist a non-http(s) url — this simulates data
    # that somehow ended up invalid regardless (bad migration, manual edit)
    # to prove the controller doesn't blindly trust the stored column.
    Repo.update_all(from(r in LectureResource, where: r.id == ^resource.id),
      set: [url: "javascript:alert(1)"]
    )

    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    conn = get(conn, ~p"/learn/resources/#{resource.id}/download")

    assert conn.status == 404
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
    resource = lecture_resource_fixture(lecture_id: lecture.id, storage_key: "lectures/notes.pdf")

    conn = get(conn, ~p"/learn/resources/#{resource.id}/download?preview=true")

    assert redirected_to(conn, 302) == "https://cdn.example.test/lectures/notes.pdf"
  end

  test "a non-admin adding ?preview=true themselves still gets 403", %{conn: conn} do
    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)
    resource = lecture_resource_fixture(lecture_id: lecture.id, storage_key: "lectures/notes.pdf")

    conn = get(conn, ~p"/learn/resources/#{resource.id}/download?preview=true")

    assert conn.status == 403
  end
end
