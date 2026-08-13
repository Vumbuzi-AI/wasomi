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

  defp submit_basics(view, title, description) do
    view
    |> form("#lecture-basics-form", %{
      "lecture" => %{"title" => title, "description" => description}
    })
    |> render_submit()
  end

  test "uploads a new lecture's video directly to Mux and saves the signed playback ID", %{
    conn: conn
  } do
    course = course_fixture()
    course_module = course_module_fixture(course_id: course.id)

    expect(Wasomi.MediaProviderMock, :create_upload, fn %Catalog.Lecture{}, [] ->
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
    submit_basics(view, "Intro to Elixir", "A first look at Elixir.")

    upload = element(view, "#lecture-video-upload")
    render_hook(upload, "create-upload", %{})
    render_hook(upload, "upload-complete", %{})
    html = render_hook(upload, "check-upload", %{})

    assert html =~ "https://image.mux.test/signed-playback-456/thumbnail.jpg?token=abc"

    html = view |> element("#lecture-video-form") |> render_submit()

    assert html =~ "Optional — add supporting documents"

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
    submit_basics(view, "Intro to Elixir", "A first look at Elixir.")

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
    submit_basics(view, "Intro to Elixir", "A first look at Elixir.")

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
    submit_basics(view, "Intro to Elixir", "A first look at Elixir.")

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
    submit_basics(view, "Intro to Elixir", "A first look at Elixir.")

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
    submit_basics(view, "Intro to Elixir", "A first look at Elixir.")

    upload = element(view, "#lecture-video-upload")
    render_hook(upload, "create-upload", %{})
    render_hook(upload, "upload-complete", %{})
    render_hook(upload, "check-upload", %{})

    # The Advanced fields are hidden by the UI once a Mux upload is
    # confirmed, but submit them anyway (bypassing the DOM) to lock in
    # that put_video_fields/2 always prefers the confirmed upload.
    render_submit(element(view, "#lecture-video-form"), %{
      "lecture" => %{
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

  test "editing a lecture with an existing video shows its thumbnail, never a raw Mux ID, and lets you remove it",
       %{conn: conn} do
    lecture =
      lecture_fixture(video_asset_id: "existing-playback-id", duration_seconds: 300)

    expect(Wasomi.MediaProviderMock, :thumbnail_url, fn %Catalog.Lecture{
                                                          video_asset_id: "existing-playback-id"
                                                        },
                                                        _user ->
      {:ok, "https://image.mux.test/existing-playback-id/thumbnail.jpg?token=abc"}
    end)

    course_module = Catalog.get_course_module!(lecture.module_id)
    course = Catalog.get_course_with_outline!(course_module.course_id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

    html = render_click(view, "edit_lecture", %{"id" => to_string(lecture.id)})

    assert html =~ "https://image.mux.test/existing-playback-id/thumbnail.jpg?token=abc"
    assert html =~ "Current video"
    refute html =~ ~s(name="lecture[video_asset_id]")
    refute html =~ ~s(name="lecture[duration_seconds]")

    html = render_click(element(view, "[aria-label='Remove selected video']"))

    refute html =~ "https://image.mux.test/existing-playback-id/thumbnail.jpg?token=abc"
    assert html =~ "Drop a video here, or click to choose one"
  end

  test "a new lecture with a resource but no video can now be saved", %{conn: conn} do
    previous_provider = Application.get_env(:wasomi, :storage_provider)
    on_exit(fn -> Application.put_env(:wasomi, :storage_provider, previous_provider) end)

    Application.put_env(
      :wasomi,
      :storage_provider,
      WasomiWeb.LectureLive.FormComponentTest.StorageMock
    )

    course = course_fixture()
    course_module = course_module_fixture(course_id: course.id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    render_click(view, "new_lecture", %{"module-id" => to_string(course_module.id)})
    submit_basics(view, "Resource-only lecture", "Reads through the attached slides.")

    # Skip the video step entirely.
    view |> element("#lecture-video-form") |> render_submit()

    resource =
      file_input(view, "#lecture-resources-form", :resources, [
        %{name: "Slides.pdf", content: "fake-pdf-bytes", type: "application/pdf"}
      ])

    html = render_upload(resource, "Slides.pdf")

    assert html =~ "100%"

    # Continue must unlock as soon as the upload finishes — it shouldn't
    # stay disabled just because the fully-uploaded file hasn't been
    # consumed into `resource_rows` yet (that only happens on submit).
    refute has_element?(view, "#lecture-resources-form button[disabled]")

    html = view |> element("#lecture-resources-form") |> render_submit()

    # Lands on the video-overview offer next (no video was added) — and
    # since the resource was just persisted by the Resources step's own
    # save, the generator can already see it (not stuck behind "save this
    # lecture with a resource first").
    assert html =~ "Generate video overview"

    lecture =
      Catalog.get_course_with_outline!(course.id).modules
      |> Enum.flat_map(& &1.lectures)
      |> Enum.find(&(&1.title == "Resource-only lecture"))

    assert lecture.video_asset_id == nil
    assert [%{name: "Slides.pdf"}] = lecture.resources
  end

  test "the wizard blocks jumping to an unreached step but allows free navigation once reached",
       %{conn: conn} do
    course = course_fixture()
    course_module = course_module_fixture(course_id: course.id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    render_click(view, "new_lecture", %{"module-id" => to_string(course_module.id)})

    step_button = fn step, label ->
      element(view, "button[phx-value-step='#{step}']", label)
    end

    # Video hasn't been reached yet — its tab is rendered disabled, so a
    # click can't even fire. The "go-to-step" handler also re-checks
    # `max_reached_step` server-side independent of this client-side
    # disabling (mirroring the analytics.ex switch_tab fix earlier this
    # session: never trust a client-supplied step value alone).
    assert_raise ArgumentError, ~r/disabled/, fn ->
      render_click(step_button.("video", "Video"))
    end

    assert has_element?(view, "#lecture-basics-form")
    refute has_element?(view, "#lecture-video-form")

    submit_basics(view, "Free navigation lecture", "Testing step navigation.")
    assert has_element?(view, "#lecture-video-form")

    # Resources hasn't been reached yet either.
    assert_raise ArgumentError, ~r/disabled/, fn ->
      render_click(step_button.("resources", "Resources"))
    end

    # Now that Video has been reached, free navigation back to Basics and
    # forward to Video again both work.
    render_click(step_button.("basics", "Basics"))
    assert has_element?(view, "#lecture-basics-form")

    render_click(step_button.("video", "Video"))
    assert has_element?(view, "#lecture-video-form")
  end

  test "questions can be skipped, and 'Add another lecture' resets to a fresh Basics step", %{
    conn: conn
  } do
    previous_provider = Application.get_env(:wasomi, :storage_provider)
    on_exit(fn -> Application.put_env(:wasomi, :storage_provider, previous_provider) end)

    Application.put_env(
      :wasomi,
      :storage_provider,
      WasomiWeb.LectureLive.FormComponentTest.StorageMock
    )

    course = course_fixture()
    course_module = course_module_fixture(course_id: course.id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    render_click(view, "new_lecture", %{"module-id" => to_string(course_module.id)})
    submit_basics(view, "First lecture", "Covers the basics.")

    # Skip the video step entirely.
    view |> element("#lecture-video-form") |> render_submit()

    resource =
      file_input(view, "#lecture-resources-form", :resources, [
        %{name: "Slides.pdf", content: "fake-pdf-bytes", type: "application/pdf"}
      ])

    render_upload(resource, "Slides.pdf")
    view |> element("#lecture-resources-form") |> render_submit()

    assert render(view) =~ "Generate video overview"

    # Continue past the video-overview offer without generating anything.
    view |> element("button", "Continue") |> render_click()

    assert has_element?(view, "#lecture-questions-form")

    html = view |> element("button", "Skip for now") |> render_click()

    assert html =~ "&quot;First lecture&quot; is saved"

    html = view |> element("button", "Add another lecture") |> render_click()

    assert has_element?(view, "#lecture-basics-form")
    refute html =~ "is saved"

    [lecture] =
      Catalog.get_course_with_outline!(course.id).modules
      |> Enum.flat_map(& &1.lectures)

    assert lecture.title == "First lecture"
  end

  test "Finish unlocks as soon as a question is actually typed in, and saves it", %{conn: conn} do
    previous_provider = Application.get_env(:wasomi, :storage_provider)
    on_exit(fn -> Application.put_env(:wasomi, :storage_provider, previous_provider) end)

    Application.put_env(
      :wasomi,
      :storage_provider,
      WasomiWeb.LectureLive.FormComponentTest.StorageMock
    )

    course = course_fixture()
    course_module = course_module_fixture(course_id: course.id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    render_click(view, "new_lecture", %{"module-id" => to_string(course_module.id)})
    submit_basics(view, "Q&A lecture", "Testing the questions step.")
    view |> element("#lecture-video-form") |> render_submit()

    resource =
      file_input(view, "#lecture-resources-form", :resources, [
        %{name: "Slides.pdf", content: "fake-pdf-bytes", type: "application/pdf"}
      ])

    render_upload(resource, "Slides.pdf")
    view |> element("#lecture-resources-form") |> render_submit()
    view |> element("button", "Continue") |> render_click()

    assert has_element?(view, "#lecture-questions-form")

    view |> element("button", "Add question") |> render_click()

    # Regression guard: Finish reads `@question_rows`, which only stayed in
    # sync with the blank row `add-question` created until this form
    # actually had a `phx-change` binding — without it, Finish stayed
    # disabled forever no matter what was typed.
    assert has_element?(view, "#lecture-questions-form button[disabled]")

    view
    |> form("#lecture-questions-form", %{
      "questions" => %{"0" => %{"question" => "How long is the course?", "answer" => "10 hours"}}
    })
    |> render_change()

    refute has_element?(view, "#lecture-questions-form button[disabled]")

    view |> element("#lecture-questions-form") |> render_submit()

    lecture =
      Catalog.get_course_with_outline!(course.id).modules
      |> Enum.flat_map(& &1.lectures)
      |> Enum.find(&(&1.title == "Q&A lecture"))

    assert [%{question: "How long is the course?", answer: "10 hours"}] = lecture.questions
  end

  test "an unrelated re-render of the course page does not lose the wizard's progress", %{
    conn: conn
  } do
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
    submit_basics(view, "Survives re-render", "Testing update/2 re-entry.")

    # Force the parent LiveView (course_show.ex) to re-render for a reason
    # completely unrelated to this lecture — this is exactly what
    # re-invokes `update/2` on the still-mounted lecture form component
    # (e.g. the same thing the :content_saved curriculum refresh does),
    # and it must not clobber the lecture this component already
    # progressed past Basics for.
    render_click(view, "switch_tab", %{"tab" => "students"})
    render_click(view, "switch_tab", %{"tab" => "curriculum"})

    upload = element(view, "#lecture-video-upload")
    render_hook(upload, "create-upload", %{})
    render_hook(upload, "upload-complete", %{})
    render_hook(upload, "check-upload", %{})

    html = view |> element("#lecture-video-form") |> render_submit()
    assert html =~ "Optional — add supporting documents"

    lecture =
      Catalog.get_course_with_outline!(course.id).modules
      |> Enum.flat_map(& &1.lectures)
      |> Enum.find(&(&1.title == "Survives re-render"))

    assert lecture.video_asset_id == "signed-playback-456"
  end

  test "triggering a video overview generation shows a pending state and hides the button", %{
    conn: conn,
    admin: admin
  } do
    lecture = lecture_fixture()
    lecture_resource_fixture(lecture_id: lecture.id, kind: :document)

    expect(Wasomi.MediaProviderMock, :thumbnail_url, fn %Catalog.Lecture{}, _user ->
      {:ok, "https://image.mux.test/thumbnail.jpg?token=abc"}
    end)

    course_module = Catalog.get_course_module!(lecture.module_id)
    course = Catalog.get_course_with_outline!(course_module.course_id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    html = render_click(view, "edit_lecture", %{"id" => to_string(lecture.id)})

    assert html =~ "Generate video overview"

    html =
      view
      |> element("#lecture-overview-generation button", "Generate video overview")
      |> render_click()

    assert html =~ "Generating"
    refute html =~ "Generate video overview"

    [generation] = Catalog.list_overview_generations_for_lecture(lecture)
    assert generation.status == :pending
    assert generation.requested_by_id == admin.id
  end

  test "cancelling a stuck generation marks it failed and restores the generate button", %{
    conn: conn
  } do
    lecture = lecture_fixture()
    lecture_resource_fixture(lecture_id: lecture.id, kind: :document)

    expect(Wasomi.MediaProviderMock, :thumbnail_url, fn %Catalog.Lecture{}, _user ->
      {:ok, "https://image.mux.test/thumbnail.jpg?token=abc"}
    end)

    course_module = Catalog.get_course_module!(lecture.module_id)
    course = Catalog.get_course_with_outline!(course_module.course_id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    render_click(view, "edit_lecture", %{"id" => to_string(lecture.id)})

    view
    |> element("#lecture-overview-generation button", "Generate video overview")
    |> render_click()

    html =
      view
      |> element("#lecture-overview-generation button", "Cancel")
      |> render_click()

    assert html =~ "Generation failed: Cancelled by admin."
    assert html =~ "Generate again"

    [generation] = Catalog.list_overview_generations_for_lecture(lecture)
    assert generation.status == :failed
  end

  test "a lecture with no document/link resources shows a hint instead of the generate button",
       %{conn: conn} do
    lecture = lecture_fixture()

    expect(Wasomi.MediaProviderMock, :thumbnail_url, fn %Catalog.Lecture{}, _user ->
      {:ok, "https://image.mux.test/thumbnail.jpg?token=abc"}
    end)

    course_module = Catalog.get_course_module!(lecture.module_id)
    course = Catalog.get_course_with_outline!(course_module.course_id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    html = render_click(view, "edit_lecture", %{"id" => to_string(lecture.id)})

    assert html =~ "Save this lecture with at least one document or link resource first."
    refute html =~ "Generate video overview"
  end

  test "the video-overview status updates live once the background job finishes", %{
    conn: conn,
    admin: admin
  } do
    lecture = lecture_fixture()
    lecture_resource_fixture(lecture_id: lecture.id, kind: :document)
    {:ok, generation} = Catalog.create_overview_generation(lecture, admin)

    expect(Wasomi.MediaProviderMock, :thumbnail_url, fn %Catalog.Lecture{}, _user ->
      {:ok, "https://image.mux.test/thumbnail.jpg?token=abc"}
    end)

    stub(Wasomi.CatalogStorageMock, :download_url, fn key ->
      {:ok, "https://cdn.example.com/#{key}"}
    end)

    course_module = Catalog.get_course_module!(lecture.module_id)
    course = Catalog.get_course_with_outline!(course_module.course_id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    render_click(view, "edit_lecture", %{"id" => to_string(lecture.id)})

    {:ok, _updated} =
      Catalog.mark_overview_generation_ready(generation, %{
        scene_count: 2,
        video_storage_key: "lecture-overviews/#{generation.id}.mp4"
      })

    # No manual "Refresh status" click — the PubSub broadcast from
    # mark_overview_generation_ready/2 should push this in automatically.
    html = render(view)

    assert html =~ "https://cdn.example.com/lecture-overviews/#{generation.id}.mp4"
    assert html =~ "Generate again"
  end

  test "using a ready video overview as the lecture video shows attaching, then attached, live",
       %{conn: conn, admin: admin} do
    lecture = lecture_fixture()
    lecture_resource_fixture(lecture_id: lecture.id, kind: :document)
    {:ok, generation} = Catalog.create_overview_generation(lecture, admin)

    {:ok, generation} =
      Catalog.mark_overview_generation_ready(generation, %{
        scene_count: 2,
        video_storage_key: "lecture-overviews/#{generation.id}.mp4"
      })

    expect(Wasomi.MediaProviderMock, :thumbnail_url, fn %Catalog.Lecture{}, _user ->
      {:ok, "https://image.mux.test/thumbnail.jpg?token=abc"}
    end)

    stub(Wasomi.CatalogStorageMock, :download_url, fn key ->
      {:ok, "https://cdn.example.com/#{key}"}
    end)

    course_module = Catalog.get_course_module!(lecture.module_id)
    course = Catalog.get_course_with_outline!(course_module.course_id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    html = render_click(view, "edit_lecture", %{"id" => to_string(lecture.id)})
    assert html =~ "Use this as the lecture video"

    html =
      view
      |> element("#lecture-overview-generation button", "Use this as the lecture video")
      |> render_click()

    assert html =~ "Attaching to the lecture"
    refute html =~ "Use this as the lecture video"
    assert Catalog.get_overview_generation!(generation.id).attach_status == :attaching

    # No manual "Refresh status" click — mirrors how generation status
    # pushes live (see the test above); the attach worker broadcasts the
    # same way once it finishes.
    Catalog.mark_overview_video_attached(Catalog.get_overview_generation!(generation.id))
    html = render(view)

    assert html =~ "This video is now the lecture"
    refute html =~ "Attaching to the lecture"
  end

  test "surfaces an error and leaves the lecture unsaved when Mux cannot start the upload", %{
    conn: conn
  } do
    lecture = lecture_fixture(video_asset_id: "old-playback-id", duration_seconds: 42)

    expect(Wasomi.MediaProviderMock, :create_upload, fn %Catalog.Lecture{id: id}, [] ->
      assert id == lecture.id
      {:error, :mux_unreachable}
    end)

    expect(Wasomi.MediaProviderMock, :thumbnail_url, fn %Catalog.Lecture{
                                                          video_asset_id: "old-playback-id"
                                                        },
                                                        _user ->
      {:ok, "https://image.mux.test/old-playback-id/thumbnail.jpg?token=abc"}
    end)

    course_module = Catalog.get_course_module!(lecture.module_id)
    course = Catalog.get_course_with_outline!(course_module.course_id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")

    render_click(view, "edit_lecture", %{"id" => to_string(lecture.id)})

    # Editing an existing video shows its thumbnail directly, with no raw
    # Mux ID ever exposed — the dropzone is always available to replace it.
    upload = element(view, "#lecture-video-upload")
    html = render_hook(upload, "create-upload", %{})

    assert html =~ "Could not start upload"

    assert Catalog.get_lecture!(lecture.id).video_asset_id == "old-playback-id"
  end

  test "switching to the link panel and saving a link keeps the link panel selected", %{
    conn: conn
  } do
    course = course_fixture()
    course_module = course_module_fixture(course_id: course.id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    render_click(view, "new_lecture", %{"module-id" => to_string(course_module.id)})
    submit_basics(view, "Link toggle lecture", "Testing resource mode toggle.")
    view |> element("#lecture-video-form") |> render_submit()

    assert has_element?(view, "button[phx-value-mode='upload'][aria-pressed='true']")

    view |> element("button[phx-value-mode='link']") |> render_click()

    assert has_element?(view, "button[phx-value-mode='link'][aria-pressed='true']")
    assert has_element?(view, "button[phx-value-mode='upload'][aria-pressed='false']")

    html =
      view
      |> form("#add-link-form", %{"url" => "https://example.com/slides.pdf"})
      |> render_submit()

    assert html =~ "https://example.com/slides.pdf"
    refute html =~ "No resources added yet."

    # Regression guard: adding a link used to re-render the resources
    # section back to its hardcoded server template, which silently reset
    # the toggle to "Upload files" every single time a link was saved.
    assert has_element?(view, "button[phx-value-mode='link'][aria-pressed='true']")
    assert has_element?(view, "button[phx-value-mode='upload'][aria-pressed='false']")
  end

  test "a link resource's DOM identity survives removing an earlier row", %{conn: conn} do
    course = course_fixture()
    course_module = course_module_fixture(course_id: course.id)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.slug}")
    render_click(view, "new_lecture", %{"module-id" => to_string(course_module.id)})
    submit_basics(view, "Link DOM identity lecture", "Testing row_id stability.")
    view |> element("#lecture-video-form") |> render_submit()

    view |> element("button[phx-value-mode='link']") |> render_click()

    view
    |> form("#add-link-form", %{"url" => "https://example.com/first"})
    |> render_submit()

    html =
      view
      |> form("#add-link-form", %{"url" => "https://example.com/second"})
      |> render_submit()

    # Regression guard: link resources always have storage_key: nil, so
    # keying their row on list index alone (the old fallback) meant every
    # link's DOM id silently shifted whenever an earlier row was removed —
    # a stable per-row id (row_id) must survive that reindex instead.
    [_first_row_id, second_row_id] =
      Regex.scan(~r/id="(lecture-resource-[a-f0-9-]+)"/, html) |> Enum.map(&List.last/1)

    view |> element("button[phx-value-index='0']") |> render_click()

    html_after_removal = render(view)

    assert html_after_removal =~ second_row_id
    refute html_after_removal =~ "https://example.com/first"
    assert html_after_removal =~ "https://example.com/second"
  end
end

defmodule WasomiWeb.LectureLive.FormComponentTest.StorageMock do
  @moduledoc """
  Mirrors `WasomiWeb.AdminLiveTest.StorageMock` — a real `storage_provider`
  is needed for `render_upload/2` to complete (the resource uploader's
  `allow_upload` calls out to it for a presigned URL during preflight), and
  no R2 credentials are configured in `config/test.exs`.
  """

  def presign_upload(_user, attrs) do
    {:ok,
     %{
       url: "https://r2.example.test/presigned-url",
       key: "lectures/draft-123/#{attrs["filename"]}",
       public_url: "https://cdn.example.test/lectures/draft-123/#{attrs["filename"]}",
       content_type: attrs["content_type"] || "application/pdf"
     }}
  end

  def delete_upload(_user, _key), do: :ok
end
