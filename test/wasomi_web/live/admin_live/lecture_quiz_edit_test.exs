defmodule WasomiWeb.AdminLive.LectureQuizEditTest do
  use WasomiWeb.ConnCase
  use Oban.Testing, repo: Wasomi.Repo

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Workers.GenerateLectureQuizWorker
  alias Wasomi.Catalog

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  defp edit_path(lecture) do
    course_module = Catalog.get_course_module!(lecture.module_id)
    course = Catalog.get_course!(course_module.course_id)
    ~p"/admin/courses/#{course.slug}/lectures/#{lecture.id}/quiz"
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  test "shows the primary video pre-selected and document resources listed", %{conn: conn} do
    lecture = lecture_fixture(video_asset_id: "playback-1")
    lecture_resource_fixture(lecture_id: lecture.id, kind: :document, name: "Slides")

    {:ok, view, html} = live(conn, edit_path(lecture))

    assert html =~ "Primary video"
    assert html =~ "Slides"

    assert view
           |> element(~s(input[name="resources[]"][value="video"]))
           |> render() =~ "checked"
  end

  test "generating with no resources selected shows a friendly error", %{conn: conn} do
    lecture = lecture_fixture(video_asset_id: "playback-1")
    {:ok, view, _html} = live(conn, edit_path(lecture))

    html =
      view
      |> render_submit("generate", %{
        "resources" => [],
        "difficulty" => "mixed",
        "question_count" => "10"
      })

    assert html =~ "Choose at least one resource"
    refute_enqueued(worker: GenerateLectureQuizWorker)
  end

  test "generating with the video selected creates the quiz, enqueues the worker, and shows progress",
       %{conn: conn} do
    lecture = lecture_fixture(video_asset_id: "playback-1")
    {:ok, view, _html} = live(conn, edit_path(lecture))

    html =
      view
      |> render_submit("generate", %{
        "resources" => ["video"],
        "difficulty" => "hard",
        "question_count" => "6"
      })

    assert html =~ "Generating"
    assert html =~ "primary video transcript"

    assert Assessments.get_lecture_quiz(lecture.id) != nil
    assert_enqueued(worker: GenerateLectureQuizWorker)
  end

  test "clamps an out-of-range question count into the allowed 3..25 window", %{conn: conn} do
    lecture = lecture_fixture(video_asset_id: "playback-1")
    {:ok, view, _html} = live(conn, edit_path(lecture))

    view
    |> render_submit("generate", %{
      "resources" => ["video"],
      "difficulty" => "mixed",
      "question_count" => "999"
    })

    quiz = Assessments.get_lecture_quiz(lecture.id)
    [generation] = Assessments.list_lecture_quiz_generations(quiz)
    assert generation.question_count_requested == 25
  end

  describe "generating a transcript for the primary video" do
    test "offers a Generate transcript button when the lecture has none yet", %{conn: conn} do
      lecture = lecture_fixture(video_asset_id: "playback-1")
      {:ok, view, html} = live(conn, edit_path(lecture))

      assert html =~ "Generate transcript"
      assert html =~ "transcript not started yet"

      view
      |> element("button[phx-click='generate_transcript']")
      |> render_click()

      transcript = Catalog.get_lecture_transcript(lecture.id)
      assert transcript.status == :pending
      assert_enqueued(worker: Wasomi.Catalog.Workers.TranscribeLecture)
    end

    test "offers a Retry transcript button when the previous attempt failed", %{conn: conn} do
      lecture = lecture_fixture(video_asset_id: "playback-1")
      Catalog.upsert_lecture_transcript(lecture.id, %{status: :failed, error: "boom"})

      {:ok, view, html} = live(conn, edit_path(lecture))

      assert html =~ "Retry transcript"

      view
      |> element("button[phx-click='generate_transcript']")
      |> render_click()

      assert Catalog.get_lecture_transcript(lecture.id).status == :pending
    end

    test "hides the button and shows a spinner while a transcript is in progress", %{conn: conn} do
      lecture = lecture_fixture(video_asset_id: "playback-1")
      Catalog.upsert_lecture_transcript(lecture.id, %{status: :processing})

      {:ok, _view, html} = live(conn, edit_path(lecture))

      refute html =~ "Generate transcript"
      assert html =~ "Transcribing…"
    end

    test "hides the button once the transcript is ready", %{conn: conn} do
      lecture = lecture_fixture(video_asset_id: "playback-1")
      Catalog.upsert_lecture_transcript(lecture.id, %{status: :ready, text: "Some text."})

      {:ok, _view, html} = live(conn, edit_path(lecture))

      refute html =~ "Generate transcript"
      refute html =~ "Transcribing…"
      assert html =~ "transcript ready"
    end

    test "updates live when the transcript worker finishes", %{conn: conn} do
      lecture = lecture_fixture(video_asset_id: "playback-1")
      {:ok, view, _html} = live(conn, edit_path(lecture))

      Catalog.upsert_lecture_transcript(lecture.id, %{status: :ready, text: "Finished."})

      assert render(view) =~ "transcript ready"
    end
  end

  describe "reviewing draft questions" do
    setup do
      lecture = lecture_fixture(video_asset_id: "playback-1")
      quiz = lecture_quiz_fixture(lecture: lecture)
      generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

      {:ok, 1} =
        Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
          draft_question_attrs()
        ])

      %{lecture: lecture, quiz: quiz}
    end

    test "publishing a single draft question flips its status", %{conn: conn, lecture: lecture} do
      {:ok, view, _html} = live(conn, edit_path(lecture))

      [question] =
        Assessments.get_lecture_quiz_with_questions!(Assessments.get_lecture_quiz(lecture.id).id).questions

      view |> element("button[phx-click='publish_question']") |> render_click()

      assert Assessments.get_lecture_quiz_question!(question.id).status == :published
    end

    test "deleting a draft question requires confirmation first", %{conn: conn, lecture: lecture} do
      {:ok, view, _html} = live(conn, edit_path(lecture))

      [question] =
        Assessments.get_lecture_quiz_with_questions!(Assessments.get_lecture_quiz(lecture.id).id).questions

      view
      |> element("button[phx-click='confirm_delete_question'][phx-value-id='#{question.id}']")
      |> render_click()

      assert has_element?(view, "#delete-question-modal")

      view |> element("#delete-question-modal button", "Delete") |> render_click()

      assert_raise Ecto.NoResultsError, fn ->
        Assessments.get_lecture_quiz_question!(question.id)
      end
    end

    test "publish all drafts publishes every draft question at once", %{
      conn: conn,
      lecture: lecture,
      quiz: quiz
    } do
      {:ok, view, _html} = live(conn, edit_path(lecture))

      view |> element("button", "Publish all drafts") |> render_click()
      view |> element("#publish-all-modal button", "Publish all") |> render_click()

      loaded = Assessments.get_lecture_quiz_with_questions!(quiz.id)
      assert Enum.all?(loaded.questions, &(&1.status == :published))
    end

    test "delete all drafts removes every draft question", %{
      conn: conn,
      lecture: lecture,
      quiz: quiz
    } do
      {:ok, view, _html} = live(conn, edit_path(lecture))

      view |> element("button", "Delete all drafts") |> render_click()
      view |> element("#delete-all-modal button", "Delete") |> render_click()

      loaded = Assessments.get_lecture_quiz_with_questions!(quiz.id)
      assert loaded.questions == []
    end
  end
end
