defmodule WasomiWeb.MediaControllerTest do
  use WasomiWeb.ConnCase

  import Mox
  import Wasomi.CatalogFixtures

  alias Wasomi.Enrollments

  setup :verify_on_exit!
  setup :register_and_log_in_user

  test "returns 403 and never calls the provider without active enrollment", %{
    conn: conn
  } do
    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)

    conn = get(conn, ~p"/media/lectures/#{lecture.id}/playback")

    assert conn.status == 403
    assert json_response(conn, 403) == %{"error" => "active enrollment required"}
  end

  test "returns only a short-lived signed HLS URL to active learners", %{
    conn: conn,
    user: user
  } do
    course = course_fixture()
    module = course_module_fixture(course_id: course.id)

    lecture =
      lecture_fixture(
        module_id: module.id,
        video_provider: :cloudflare,
        video_asset_id: "playback-123"
      )

    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    expect(Wasomi.MediaProviderMock, :playback_token, fn ^lecture, ^user, 300 ->
      {:ok, "signed.jwt.token"}
    end)

    conn = get(conn, ~p"/media/lectures/#{lecture.id}/playback")

    assert %{"url" => url, "expires_in" => 300} = json_response(conn, 200)

    assert url ==
             "https://customer-test-customer-code.cloudflarestream.com/signed.jwt.token/manifest/video.m3u8"

    refute url =~ ".mp4"
  end

  test "an admin with ?preview=true gets a signed URL despite no enrollment", %{
    conn: conn,
    user: user
  } do
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    conn = log_in_user(conn, admin)

    course = course_fixture()
    module = course_module_fixture(course_id: course.id)

    lecture =
      lecture_fixture(
        module_id: module.id,
        video_provider: :cloudflare,
        video_asset_id: "playback-123"
      )

    expect(Wasomi.MediaProviderMock, :playback_token, fn ^lecture, ^admin, 300 ->
      {:ok, "signed.jwt.token"}
    end)

    conn = get(conn, ~p"/media/lectures/#{lecture.id}/playback?preview=true")

    assert %{"url" => url} = json_response(conn, 200)

    assert url ==
             "https://customer-test-customer-code.cloudflarestream.com/signed.jwt.token/manifest/video.m3u8"
  end

  test "a non-admin adding ?preview=true themselves still gets 403", %{conn: conn} do
    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)

    conn = get(conn, ~p"/media/lectures/#{lecture.id}/playback?preview=true")

    assert conn.status == 403
    assert json_response(conn, 403) == %{"error" => "active enrollment required"}
  end
end
