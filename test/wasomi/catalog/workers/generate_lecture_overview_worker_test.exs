defmodule Wasomi.Catalog.Workers.GenerateLectureOverviewWorkerTest do
  use Wasomi.DataCase

  import Wasomi.{AccountsFixtures, CatalogFixtures}
  import Mox

  alias Wasomi.Catalog
  alias Wasomi.Catalog.Workers.GenerateLectureOverviewWorker

  setup :verify_on_exit!

  setup do
    admin = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(admin, :admin)
    lecture = lecture_fixture()
    lecture_resource_fixture(lecture_id: lecture.id, kind: :document)

    {:ok, generation} = Catalog.create_overview_generation(lecture, admin)

    %{lecture: lecture, admin: admin, generation: generation}
  end

  defp args(generation), do: %{"generation_id" => generation.id}

  defp scene, do: %{narration: "Here is what happens next.", slide_text: "Step one"}

  defp stub_pipeline(scenes \\ [scene()]) do
    stub(Wasomi.CatalogStorageMock, :download, fn _key -> {:ok, "%PDF-1.4 fake"} end)
    stub(Wasomi.PdfExtractorMock, :extract_text, fn _binary -> {:ok, "Extracted text."} end)

    stub(Wasomi.OverviewScriptGeneratorMock, :generate_script, fn _text, _opts ->
      {:ok, scenes}
    end)

    stub(Wasomi.OverviewNarratorMock, :synthesize, fn _text, _opts -> {:ok, "mp3-bytes"} end)
    stub(Wasomi.OverviewImageGeneratorMock, :generate, fn _text, _opts -> {:ok, "img-bytes"} end)
    stub(Wasomi.SlideRendererMock, :render, fn _slide_text, _opts -> {:ok, "png-bytes"} end)

    stub(Wasomi.VideoAssemblerMock, :assemble, fn _scenes, output_path ->
      File.write!(output_path, "mp4-bytes")
      {:ok, output_path}
    end)

    stub(Wasomi.CatalogStorageMock, :upload, fn _key, _bytes -> :ok end)
  end

  test "gathers resource text, generates a script, assembles a video, and marks the generation ready",
       %{generation: generation} do
    stub_pipeline([scene(), scene()])

    expect(Wasomi.OverviewScriptGeneratorMock, :generate_script, fn text, _opts ->
      assert text == "Extracted text."
      {:ok, [scene(), scene()]}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateLectureOverviewWorker, args(generation), [])

    updated = Catalog.get_overview_generation!(generation.id)
    assert updated.status == :ready
    assert updated.scene_count == 2
    assert updated.video_storage_key == "lecture-overviews/#{generation.id}.mp4"
  end

  test "preserves scene order in the assembled video even though scenes render concurrently", %{
    generation: generation
  } do
    scenes = [
      %{narration: "First scene.", slide_text: "One"},
      %{narration: "Second scene.", slide_text: "Two"},
      %{narration: "Third scene.", slide_text: "Three"}
    ]

    stub_pipeline(scenes)

    # The first scene finishes rendering LAST, deliberately out of order,
    # to prove the concurrent render still hands the assembler scenes
    # back in their original order rather than completion order.
    stub(Wasomi.OverviewNarratorMock, :synthesize, fn text, _opts ->
      if text == "First scene.", do: Process.sleep(200)
      {:ok, "mp3-bytes"}
    end)

    expect(Wasomi.VideoAssemblerMock, :assemble, fn rendered_scenes, output_path ->
      assert Enum.map(rendered_scenes, &(&1.image_path |> Path.basename())) == [
               "scene-0.png",
               "scene-1.png",
               "scene-2.png"
             ]

      File.write!(output_path, "mp4-bytes")
      {:ok, output_path}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateLectureOverviewWorker, args(generation), [])
  end

  test "renders each scene's narration and slide through the configured adapters", %{
    generation: generation
  } do
    stub_pipeline()

    expect(Wasomi.OverviewNarratorMock, :synthesize, fn text, _opts ->
      assert text == "Here is what happens next."
      {:ok, "mp3-bytes"}
    end)

    expect(Wasomi.OverviewImageGeneratorMock, :generate, fn text, _opts ->
      assert text == "Here is what happens next."
      {:ok, "img-bytes"}
    end)

    expect(Wasomi.SlideRendererMock, :render, fn slide_text, opts ->
      assert slide_text == "Step one"
      assert Keyword.get(opts, :image) == "img-bytes"
      {:ok, "png-bytes"}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateLectureOverviewWorker, args(generation), [])
  end

  test "a failed scene illustration falls back to a plain slide instead of failing the generation",
       %{generation: generation} do
    stub_pipeline()

    stub(Wasomi.OverviewImageGeneratorMock, :generate, fn _text, _opts ->
      {:error, :rate_limited}
    end)

    expect(Wasomi.SlideRendererMock, :render, fn _slide_text, opts ->
      assert Keyword.get(opts, :image) == nil
      {:ok, "png-bytes"}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateLectureOverviewWorker, args(generation), [])
    assert Catalog.get_overview_generation!(generation.id).status == :ready
  end

  test "a lecture with no document/link resources fails without calling any AI adapter", %{
    admin: admin
  } do
    bare_lecture = lecture_fixture()
    {:ok, bare_generation} = Catalog.create_overview_generation(bare_lecture, admin)

    assert {:error, :no_source_resources} =
             Oban.Testing.perform_job(GenerateLectureOverviewWorker, args(bare_generation),
               attempt: 1,
               max_attempts: 1
             )

    updated = Catalog.get_overview_generation!(bare_generation.id)
    assert updated.status == :failed
    assert updated.error_message =~ "no document or link resources"
  end

  test "only marks the generation :failed on the job's last Oban attempt", %{
    generation: generation
  } do
    stub(Wasomi.CatalogStorageMock, :download, fn _key -> {:ok, "%PDF-1.4 fake"} end)
    stub(Wasomi.PdfExtractorMock, :extract_text, fn _binary -> {:error, :broken_pdf} end)

    assert {:error, {:all_resources_unreadable, [{_name, :broken_pdf}]}} =
             Oban.Testing.perform_job(GenerateLectureOverviewWorker, args(generation),
               attempt: 1,
               max_attempts: 3
             )

    assert Catalog.get_overview_generation!(generation.id).status == :processing

    assert {:error, {:all_resources_unreadable, [{_name, :broken_pdf}]}} =
             Oban.Testing.perform_job(GenerateLectureOverviewWorker, args(generation),
               attempt: 3,
               max_attempts: 3
             )

    updated = Catalog.get_overview_generation!(generation.id)
    assert updated.status == :failed
    assert updated.error_message =~ "broken_pdf"
  end
end
