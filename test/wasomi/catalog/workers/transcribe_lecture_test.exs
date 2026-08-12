defmodule Wasomi.Catalog.Workers.TranscribeLectureTest do
  use Wasomi.DataCase

  import Wasomi.CatalogFixtures
  import Mox

  alias Wasomi.Catalog
  alias Wasomi.Catalog.Workers.TranscribeLecture

  setup :verify_on_exit!

  setup do
    %{lecture: lecture_fixture(video_provider: :mux, video_asset_id: "playback-123")}
  end

  defp args(lecture), do: %{"lecture_id" => lecture.id}

  defp stub_download_url(url \\ "https://stream.mux.test/playback-123/low.mp4?token=abc") do
    expect(Wasomi.MediaProviderMock, :download_url, fn _lecture -> {:ok, url} end)
  end

  test "transcribes the lecture's video and marks the transcript ready", %{lecture: lecture} do
    stub_download_url()

    expect(Wasomi.TranscriberMock, :transcribe, fn url ->
      assert url == "https://stream.mux.test/playback-123/low.mp4?token=abc"
      {:ok, "Welcome to the lecture."}
    end)

    assert :ok = Oban.Testing.perform_job(TranscribeLecture, args(lecture), [])

    transcript = Catalog.get_lecture_transcript(lecture.id)
    assert transcript.status == :ready
    assert transcript.text == "Welcome to the lecture."
    assert transcript.error == nil
  end

  test "marks the transcript processing before calling the transcriber", %{lecture: lecture} do
    stub_download_url()

    expect(Wasomi.TranscriberMock, :transcribe, fn _url ->
      assert Catalog.get_lecture_transcript(lecture.id).status == :processing
      {:ok, "some text"}
    end)

    assert :ok = Oban.Testing.perform_job(TranscribeLecture, args(lecture), [])
  end

  test "a media download-url failure leaves the transcript processing before the final attempt",
       %{lecture: lecture} do
    expect(Wasomi.MediaProviderMock, :download_url, fn _lecture ->
      {:error, :unsupported_video_provider}
    end)

    assert {:error, :unsupported_video_provider} =
             Oban.Testing.perform_job(TranscribeLecture, args(lecture),
               attempt: 1,
               max_attempts: 5
             )

    transcript = Catalog.get_lecture_transcript(lecture.id)
    assert transcript.status == :processing
  end

  test "a media download-url failure marks the transcript failed on the last attempt", %{
    lecture: lecture
  } do
    expect(Wasomi.MediaProviderMock, :download_url, fn _lecture ->
      {:error, :unsupported_video_provider}
    end)

    assert {:error, :unsupported_video_provider} =
             Oban.Testing.perform_job(TranscribeLecture, args(lecture),
               attempt: 5,
               max_attempts: 5
             )

    transcript = Catalog.get_lecture_transcript(lecture.id)
    assert transcript.status == :failed
    assert transcript.error =~ "unsupported_video_provider"
  end

  test "a transcriber failure marks the transcript failed on the last attempt", %{
    lecture: lecture
  } do
    stub_download_url()

    expect(Wasomi.TranscriberMock, :transcribe, fn _url ->
      {:error, :openai_api_key_not_configured}
    end)

    assert {:error, :openai_api_key_not_configured} =
             Oban.Testing.perform_job(TranscribeLecture, args(lecture),
               attempt: 5,
               max_attempts: 5
             )

    transcript = Catalog.get_lecture_transcript(lecture.id)
    assert transcript.status == :failed
    assert transcript.error =~ "openai_api_key_not_configured"
  end

  test "re-running the job for the same lecture replaces the previous transcript", %{
    lecture: lecture
  } do
    Catalog.upsert_lecture_transcript(lecture.id, %{
      status: :ready,
      text: "Stale transcript.",
      error: nil
    })

    stub_download_url()
    expect(Wasomi.TranscriberMock, :transcribe, fn _url -> {:ok, "Fresh transcript."} end)

    assert :ok = Oban.Testing.perform_job(TranscribeLecture, args(lecture), [])

    assert Catalog.get_lecture_transcript(lecture.id).text == "Fresh transcript."
  end
end
