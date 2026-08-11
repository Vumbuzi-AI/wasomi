defmodule WasomiWeb.LectureLive.FormComponentTest do
  use WasomiWeb.ConnCase

  import ExUnit.CaptureLog
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

  test "uploads a new lecture's video directly to Mux and saves the signed playback ID", %{
    conn: conn
  } do
    course = course_fixture()
    course_module = course_module_fixture(course_id: course.id)

    expect(Wasomi.MediaProviderMock, :create_upload, fn %Catalog.Lecture{id: nil}, [] ->
      {:ok, %{id: "upload-123", url: "https://storage.mux.test/direct-upload"}}
    end)

    expect(Wasomi.MediaProviderMock, :upload_status, fn "upload-123" ->
      {:ok, {:ready, "signed-playback-456", 612}}
    end)

    expect(Wasomi.MediaProviderMock, :thumbnail_url, fn %Catalog.Lecture{
                                                          video_asset_id: "signed-playback-456"
                                                        },
                                                        _user ->
      {:ok, "https://image.mux.test/signed-playback-456/thumbnail.jpg?token=abc"}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

    render_click(view, "new_lecture", %{"module-id" => to_string(course_module.id)})

    upload = element(view, "#lecture-video-upload")
    render_hook(upload, "create-upload", %{})
    render_hook(upload, "upload-complete", %{})
    html = render_hook(upload, "check-upload", %{})

    assert html =~ "https://image.mux.test/signed-playback-456/thumbnail.jpg?token=abc"

    html =
      view
      |> form("#lecture-form", %{
        "lecture" => %{
          "title" => "Intro to Elixir",
          "description" => "A first look at Elixir."
        }
      })
      |> render_submit()

    assert html =~ "Lecture created successfully"

    lecture =
      Catalog.get_course_with_outline!(course.id).modules
      |> Enum.flat_map(& &1.lectures)
      |> Enum.find(&(&1.title == "Intro to Elixir"))

    assert lecture.video_provider == :mux
    assert lecture.video_asset_id == "signed-playback-456"
    assert lecture.duration_seconds == 612
  end

  test "shows the client-captured local preview immediately, then the real Mux thumbnail once ready",
       %{conn: conn} do
    course = course_fixture()
    course_module = course_module_fixture(course_id: course.id)

    expect(Wasomi.MediaProviderMock, :create_upload, fn %Catalog.Lecture{}, [] ->
      {:ok, %{id: "upload-123", url: "https://storage.mux.test/direct-upload"}}
    end)

    expect(Wasomi.MediaProviderMock, :upload_status, fn "upload-123" ->
      {:ok, {:ready, "signed-playback-456", 612}}
    end)

    expect(Wasomi.MediaProviderMock, :thumbnail_url, fn %Catalog.Lecture{}, _user ->
      {:ok, "https://image.mux.test/signed-playback-456/thumbnail.jpg?token=abc"}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    render_click(view, "new_lecture", %{"module-id" => to_string(course_module.id)})

    upload = element(view, "#lecture-video-upload")
    render_hook(upload, "create-upload", %{})
    html = render_hook(upload, "local-preview", %{"data_url" => "data:image/jpeg;base64,abc123"})

    assert html =~ "data:image/jpeg;base64,abc123"

    render_hook(upload, "upload-complete", %{})
    html = render_hook(upload, "check-upload", %{})

    assert html =~ "https://image.mux.test/signed-playback-456/thumbnail.jpg?token=abc"
    refute html =~ "data:image/jpeg;base64,abc123"
  end

  test "handles malformed create-upload payloads without crashing", %{conn: conn} do
    course = course_fixture()
    course_module = course_module_fixture(course_id: course.id)

    expect(Wasomi.MediaProviderMock, :create_upload, fn %Catalog.Lecture{}, [] ->
      {:ok, %{id: "upload-123", url: "https://storage.mux.test/direct-upload"}}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    render_click(view, "new_lecture", %{"module-id" => to_string(course_module.id)})

    upload = element(view, "#lecture-video-upload")

    html =
      render_hook(upload, "create-upload", %{
        "filename" => String.duplicate("a", 5000) <> ".mp4",
        "size" => "not-a-number"
      })

    assert html =~ "Uploading directly to Mux"
    refute html =~ String.duplicate("a", 5000)
  end

  test "surfaces an error when the direct PUT to Mux fails partway through", %{conn: conn} do
    course = course_fixture()
    course_module = course_module_fixture(course_id: course.id)

    expect(Wasomi.MediaProviderMock, :create_upload, fn %Catalog.Lecture{}, [] ->
      {:ok, %{id: "upload-123", url: "https://storage.mux.test/direct-upload"}}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    render_click(view, "new_lecture", %{"module-id" => to_string(course_module.id)})

    upload = element(view, "#lecture-video-upload")
    render_hook(upload, "create-upload", %{})
    html = render_hook(upload, "upload-failed", %{"status" => 500})

    assert html =~ "The upload to Mux failed (HTTP 500)"
  end

  test "logs and surfaces a friendly message when the Mux adapter call raises", %{conn: conn} do
    course = course_fixture()
    course_module = course_module_fixture(course_id: course.id)

    expect(Wasomi.MediaProviderMock, :create_upload, fn %Catalog.Lecture{}, [] ->
      raise "MUX_TOKEN_ID is not configured"
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    render_click(view, "new_lecture", %{"module-id" => to_string(course_module.id)})

    upload = element(view, "#lecture-video-upload")

    {html, log} = with_log(fn -> render_hook(upload, "create-upload", %{}) end)

    assert html =~ "Could not start upload: MUX_TOKEN_ID is not configured"
    assert log =~ "Media call raised"
    assert log =~ "MUX_TOKEN_ID is not configured"
  end

  test "the confirmed Mux upload always wins over stray video_asset_id/duration_seconds params",
       %{conn: conn} do
    course = course_fixture()
    course_module = course_module_fixture(course_id: course.id)

    expect(Wasomi.MediaProviderMock, :create_upload, fn %Catalog.Lecture{}, [] ->
      {:ok, %{id: "upload-123", url: "https://storage.mux.test/direct-upload"}}
    end)

    expect(Wasomi.MediaProviderMock, :upload_status, fn "upload-123" ->
      {:ok, {:ready, "signed-playback-456", 612}}
    end)

    expect(Wasomi.MediaProviderMock, :thumbnail_url, fn %Catalog.Lecture{}, _user ->
      {:ok, "https://image.mux.test/signed-playback-456/thumbnail.jpg?token=abc"}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    render_click(view, "new_lecture", %{"module-id" => to_string(course_module.id)})

    upload = element(view, "#lecture-video-upload")
    render_hook(upload, "create-upload", %{})
    render_hook(upload, "upload-complete", %{})
    render_hook(upload, "check-upload", %{})

    # The Advanced fields are hidden by the UI once a Mux upload is
    # confirmed, but submit them anyway (bypassing the DOM) to lock in
    # that put_video_fields/2 always prefers the confirmed upload.
    render_submit(element(view, "#lecture-form"), %{
      "lecture" => %{
        "title" => "Intro to Elixir",
        "description" => "A first look at Elixir.",
        "position" => "1",
        "video_asset_id" => "attacker-supplied-id",
        "duration_seconds" => "999"
      }
    })

    lecture =
      Catalog.get_course_with_outline!(course.id).modules
      |> Enum.flat_map(& &1.lectures)
      |> Enum.find(&(&1.title == "Intro to Elixir"))

    assert lecture.video_asset_id == "signed-playback-456"
    assert lecture.duration_seconds == 612
  end

  test "surfaces an error and leaves the lecture unsaved when Mux cannot start the upload", %{
    conn: conn
  } do
    lecture = lecture_fixture(video_asset_id: "old-playback-id", duration_seconds: 42)

    expect(Wasomi.MediaProviderMock, :create_upload, fn %Catalog.Lecture{id: id}, [] ->
      assert id == lecture.id
      {:error, :mux_unreachable}
    end)

    course_module = Catalog.get_course_module!(lecture.module_id)
    course = Catalog.get_course_with_outline!(course_module.course_id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

    render_click(view, "edit_lecture", %{"id" => to_string(lecture.id)})

    # The dropzone is hidden while an existing Mux ID is present (only one
    # video source is shown at a time); clear it to reveal the dropzone,
    # mirroring an admin who wants to replace the current video.
    view
    |> form("#lecture-form", %{"lecture" => %{"video_asset_id" => ""}})
    |> render_change()

    upload = element(view, "#lecture-video-upload")
    html = render_hook(upload, "create-upload", %{})

    assert html =~ "Could not start upload"

    assert Catalog.get_lecture!(lecture.id).video_asset_id == "old-playback-id"
  end
end
