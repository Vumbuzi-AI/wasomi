defmodule WasomiWeb.AdminLectureVideoLiveTest do
  use WasomiWeb.ConnCase

  import Mox
  import Phoenix.LiveViewTest
  import Wasomi.CatalogFixtures

  alias Wasomi.{Accounts, Catalog}

  setup :verify_on_exit!

  setup %{conn: conn} do
    user = Wasomi.AccountsFixtures.user_fixture()
    {:ok, admin} = Accounts.update_user_role(user, :admin)
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  test "creates a direct upload and stores the signed playback ID when ready", %{
    conn: conn,
    admin: admin
  } do
    lecture = lecture_fixture(video_asset_id: "old-playback-id", duration_seconds: 42)

    expect(Wasomi.MediaProviderMock, :create_upload, fn ^lecture, opts ->
      assert opts == []
      {:ok, %{id: "upload-123", url: "https://storage.mux.test/direct-upload"}}
    end)

    expect(Wasomi.MediaProviderMock, :upload_status, fn "upload-123" ->
      {:ok, {:ready, "signed-playback-456", 612}}
    end)

    assert {:ok, view, html} = live(conn, ~p"/admin/lectures/#{lecture.id}/video")
    assert html =~ "Mux direct upload"

    render_hook(view, "create-upload", %{})
    render_hook(view, "upload-complete", %{})
    html = render_hook(view, "check-upload", %{})

    assert html =~ "Video is ready for protected playback."

    updated = Catalog.get_lecture!(lecture.id)
    assert updated.video_provider == :mux
    assert updated.video_asset_id == "signed-playback-456"
    assert updated.duration_seconds == 612
    assert admin.role == :admin
  end

  test "rejects non-admin learners", %{conn: _conn} do
    learner = Wasomi.AccountsFixtures.user_fixture()
    learner_conn = build_conn() |> log_in_user(learner)
    lecture = lecture_fixture()

    assert {:error, {:redirect, %{to: "/"}}} =
             live(learner_conn, ~p"/admin/lectures/#{lecture.id}/video")
  end
end
