defmodule WasomiWeb.LectureLive.FormComponentTest do
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

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

    render_click(view, "new_lecture", %{"module-id" => to_string(course_module.id)})

    upload = element(view, "#lecture-video-upload")
    render_hook(upload, "create-upload", %{})
    render_hook(upload, "upload-complete", %{})
    html = render_hook(upload, "check-upload", %{})

    assert html =~ "Video is ready for protected playback."

    html =
      view
      |> form("#lecture-form", %{
        "lecture" => %{
          "title" => "Intro to Elixir",
          "description" => "A first look at Elixir.",
          "position" => "1"
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

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

    render_click(view, "edit_lecture", %{"id" => to_string(lecture.id)})

    upload = element(view, "#lecture-video-upload")
    html = render_hook(upload, "create-upload", %{})

    assert html =~ "Could not start upload"

    assert Catalog.get_lecture!(lecture.id).video_asset_id == "old-playback-id"
  end
end
