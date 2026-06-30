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
        video_provider: :mux,
        video_asset_id: "playback-123"
      )

    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    expect(Wasomi.MediaProviderMock, :playback_token, fn ^lecture, ^user, 300 ->
      {:ok, "signed.jwt.token"}
    end)

    conn = get(conn, ~p"/media/lectures/#{lecture.id}/playback")

    assert %{"url" => url, "expires_in" => 300} = json_response(conn, 200)
    assert url == "https://stream.mux.com/playback-123.m3u8?token=signed.jwt.token"
    refute url =~ ".mp4"
  end
end
