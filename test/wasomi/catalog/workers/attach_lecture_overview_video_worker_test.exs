defmodule Wasomi.Catalog.Workers.AttachLectureOverviewVideoWorkerTest do
  use Wasomi.DataCase

  import Wasomi.{AccountsFixtures, CatalogFixtures}
  import Mox

  alias Wasomi.Catalog
  alias Wasomi.Catalog.Workers.AttachLectureOverviewVideoWorker

  setup :verify_on_exit!

  setup do
    admin = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(admin, :admin)
    lecture = lecture_fixture()

    {:ok, generation} = Catalog.create_overview_generation(lecture, admin)

    {:ok, generation} =
      Catalog.mark_overview_generation_ready(generation, %{
        scene_count: 3,
        video_storage_key: "lecture-overviews/#{generation.id}.mp4"
      })

    generation = Catalog.mark_overview_video_attaching(generation)

    %{lecture: lecture, admin: admin, generation: generation}
  end

  defp args(generation), do: %{"generation_id" => generation.id}

  test "creates the Mux asset from the stored video's URL, then snoozes to poll it",
       %{generation: generation} do
    stub(Wasomi.CatalogStorageMock, :download_url, fn key ->
      {:ok, "https://cdn.example.test/#{key}"}
    end)

    expect(Wasomi.MediaProviderMock, :create_asset_from_url, fn lecture, url, _opts ->
      assert lecture.id == generation.lecture_id
      assert url == "https://cdn.example.test/#{generation.video_storage_key}"
      {:ok, %{asset_id: "asset_123"}}
    end)

    assert {:snooze, 10} =
             Oban.Testing.perform_job(AttachLectureOverviewVideoWorker, args(generation), [])

    updated = Catalog.get_overview_generation!(generation.id)
    assert updated.attach_status == :attaching
    assert updated.attach_asset_id == "asset_123"
  end

  test "snoozes again while the Mux asset is still processing", %{generation: generation} do
    {:ok, generation} =
      Catalog.get_overview_generation!(generation.id)
      |> Ecto.Changeset.change(attach_asset_id: "asset_123")
      |> Wasomi.Repo.update()

    stub(Wasomi.MediaProviderMock, :asset_status, fn "asset_123" -> {:ok, :processing} end)

    assert {:snooze, 10} =
             Oban.Testing.perform_job(AttachLectureOverviewVideoWorker, args(generation), [])

    updated = Catalog.get_overview_generation!(generation.id)
    assert updated.attach_status == :attaching
  end

  test "attaches the video to the lecture once the Mux asset is ready", %{
    generation: generation
  } do
    {:ok, generation} =
      Catalog.get_overview_generation!(generation.id)
      |> Ecto.Changeset.change(attach_asset_id: "asset_123")
      |> Wasomi.Repo.update()

    stub(Wasomi.MediaProviderMock, :asset_status, fn "asset_123" ->
      {:ok, {:ready, "playback_abc", 42}}
    end)

    assert :ok = Oban.Testing.perform_job(AttachLectureOverviewVideoWorker, args(generation), [])

    updated = Catalog.get_overview_generation!(generation.id)
    assert updated.attach_status == :attached

    lecture = Catalog.get_lecture!(generation.lecture_id)
    assert lecture.video_provider == :mux
    assert lecture.video_asset_id == "playback_abc"
    assert lecture.duration_seconds == 42
  end

  test "only marks attach_status :attach_failed on the job's last Oban attempt", %{
    generation: generation
  } do
    {:ok, generation} =
      Catalog.get_overview_generation!(generation.id)
      |> Ecto.Changeset.change(attach_asset_id: "asset_123")
      |> Wasomi.Repo.update()

    stub(Wasomi.MediaProviderMock, :asset_status, fn "asset_123" ->
      {:error, {:mux_asset_errored, ["boom"]}}
    end)

    assert {:error, {:mux_asset_errored, ["boom"]}} =
             Oban.Testing.perform_job(AttachLectureOverviewVideoWorker, args(generation),
               attempt: 1,
               max_attempts: 5
             )

    assert Catalog.get_overview_generation!(generation.id).attach_status == :attaching

    assert {:error, {:mux_asset_errored, ["boom"]}} =
             Oban.Testing.perform_job(AttachLectureOverviewVideoWorker, args(generation),
               attempt: 5,
               max_attempts: 5
             )

    updated = Catalog.get_overview_generation!(generation.id)
    assert updated.attach_status == :attach_failed
    assert updated.attach_error_message =~ "mux_asset_errored"
  end

  test "formats a Mux API error as a readable message instead of a raw term dump", %{
    generation: generation
  } do
    stub(Wasomi.CatalogStorageMock, :download_url, fn key ->
      {:ok, "https://cdn.example.test/#{key}"}
    end)

    stub(Wasomi.MediaProviderMock, :create_asset_from_url, fn _lecture, _url, _opts ->
      {:error,
       {:mux,
        %{"messages" => ["Free plan is limited to 10 assets"], "type" => "invalid_parameters"}}}
    end)

    Oban.Testing.perform_job(AttachLectureOverviewVideoWorker, args(generation),
      attempt: 5,
      max_attempts: 5
    )

    updated = Catalog.get_overview_generation!(generation.id)
    assert updated.attach_status == :attach_failed

    assert updated.attach_error_message ==
             "Mux rejected the request (Free plan is limited to 10 assets)"
  end
end
