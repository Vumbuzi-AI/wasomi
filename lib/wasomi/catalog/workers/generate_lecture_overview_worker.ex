defmodule Wasomi.Catalog.Workers.GenerateLectureOverviewWorker do
  @moduledoc """
  Turns a video-less lecture's attached `:document`/`:link` resources
  into a narrated video overview.

  Gathers source text -> generates a draft script via a swappable AI
  adapter -> renders each scene's narration/slide/illustration -> marks
  the generation `:ready` for review, never auto-attached (see
  `Wasomi.Catalog.Workers.AttachLectureOverviewVideoWorker` for that
  explicit next step). The generation record only flips to `:failed` on
  the job's last Oban attempt, so a transient failure doesn't flicker the
  admin UI before a retry quietly succeeds.

  Closed captions come from Mux's own `generated_subtitles` (Whisper-based,
  attached once the video reaches Mux via
  `Wasomi.Catalog.Workers.AttachLectureOverviewVideoWorker`) rather than
  anything built here — this worker knows the exact narration text ahead
  of time, but a video-less lecture with a real admin-uploaded video
  never does, so standardizing on Mux's own captions covers both instead
  of maintaining two different mechanisms.
  """

  use Oban.Worker,
    queue: :lecture_overview,
    max_attempts: 3

  require Logger

  alias Wasomi.{Catalog, Repo}

  # Without an explicit timeout, Oban's default is :infinity — a hang
  # anywhere in this pipeline (a stuck `ffmpeg`/`ffprobe` System.cmd call
  # has no timeout of its own, unlike the HTTP-based steps) would block
  # the job forever with no error and no retry, indistinguishable from a
  # genuinely long-running generation. 25 minutes is generous for the
  # realistic worst case (up to 8 scenes, each doing narration + image
  # generation) while still bounding a real hang instead of leaving it
  # infinite.
  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(25)

  @impl Oban.Worker
  def perform(%Oban.Job{
        attempt: attempt,
        max_attempts: max_attempts,
        args: %{"generation_id" => generation_id}
      }) do
    generation = Catalog.get_overview_generation!(generation_id)

    case run(generation) do
      :ok ->
        :ok

      {:error, reason} ->
        if attempt >= max_attempts do
          Catalog.mark_overview_generation_failed(generation, format_failure(reason))
        end

        {:error, reason}
    end
  end

  defp run(generation) do
    Catalog.mark_overview_generation_processing(generation)
    lecture = generation.lecture_id |> Catalog.get_lecture!() |> Repo.preload(:resources)

    Wasomi.TempDir.with_tmp_dir(fn work_dir ->
      with {:ok, text} <- source_text(lecture),
           {:ok, scenes} <- script_generator().generate_script(text, []),
           {:ok, rendered_scenes} <- render_scenes(scenes, work_dir),
           output_path = Path.join(work_dir, "overview.mp4"),
           {:ok, video_path} <- video_assembler().assemble(rendered_scenes, output_path),
           {:ok, video_bytes} <- File.read(video_path),
           video_key = storage_key(generation),
           :ok <- storage().upload(video_key, video_bytes) do
        {:ok, _updated} =
          Catalog.mark_overview_generation_ready(generation, %{
            scene_count: length(scenes),
            video_storage_key: video_key
          })

        :ok
      end
    end)
  end

  # One unreadable resource (e.g. a link whose site blocks non-browser
  # requests with a 403) shouldn't sink the whole generation when other
  # attached resources read fine on their own — skip it and note why,
  # rather than halting on the first failure.
  defp source_text(lecture) do
    lecture.resources
    |> Enum.filter(&(&1.kind in [:document, :link]))
    |> case do
      [] ->
        {:error, :no_source_resources}

      resources ->
        {texts, failures} =
          Enum.reduce(resources, {[], []}, fn resource, {texts, failures} ->
            case resource_text(resource) do
              {:ok, text} -> {[text | texts], failures}
              {:error, reason} -> {texts, [{resource.name, reason} | failures]}
            end
          end)

        texts = Enum.reverse(texts)
        failures = Enum.reverse(failures)

        if failures != [] do
          Logger.warning(
            "Overview generation for lecture #{lecture.id} skipped #{length(failures)} " <>
              "unreadable resource(s): " <>
              Enum.map_join(failures, "; ", fn {name, reason} ->
                "#{name} (#{format_resource_error(reason)})"
              end)
          )
        end

        case texts do
          [] -> {:error, {:all_resources_unreadable, failures}}
          _texts -> {:ok, Enum.join(texts, "\n\n")}
        end
    end
  end

  defp format_resource_error({:http_error, status}), do: "HTTP #{status}"
  defp format_resource_error({:http_error, status, _body}), do: "HTTP #{status}"
  defp format_resource_error(reason), do: inspect(reason)

  defp format_failure(:no_source_resources), do: "This lecture has no document or link resources."

  defp format_failure({:all_resources_unreadable, failures}) do
    "Couldn't read any of the attached resources: " <>
      Enum.map_join(failures, "; ", fn {name, reason} ->
        "#{name} (#{format_resource_error(reason)})"
      end)
  end

  defp format_failure(reason), do: inspect(reason)

  defp resource_text(%{kind: :document, storage_key: key}) do
    with {:ok, bytes} <- storage().download(key) do
      pdf_extractor().extract_text(bytes)
    end
  end

  defp resource_text(%{kind: :link, url: url}), do: link_text_fetcher().fetch_text(url)

  # Each scene is independent (its own narration/image/audio), so
  # rendering them one at a time — the original version of this function
  # — left most of the wall-clock time spent waiting on TTS/image-gen API
  # calls that could easily run concurrently instead. `Task.async_stream/3`
  # preserves input order in its results despite running out of order,
  # which is exactly what's needed since scene order matters for the
  # assembled video. Bounded at 3 concurrent scenes: real headroom
  # (ChromicPDF's screenshot pool defaults to ~4 sessions on this host)
  # without hammering the image-gen/TTS APIs with a whole scene list at
  # once.
  @scene_concurrency 3
  @scene_render_timeout :timer.minutes(3)

  defp render_scenes(scenes, work_dir) do
    scenes
    |> Enum.with_index()
    |> Task.async_stream(
      fn {scene, index} -> render_scene(scene, index, work_dir) end,
      max_concurrency: @scene_concurrency,
      timeout: @scene_render_timeout,
      on_timeout: :kill_task
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, rendered}}, {:ok, acc} -> {:cont, {:ok, [rendered | acc]}}
      {:ok, {:error, reason}}, {:ok, _acc} -> {:halt, {:error, reason}}
      {:exit, reason}, {:ok, _acc} -> {:halt, {:error, {:scene_render_failed, reason}}}
    end)
    |> case do
      {:ok, rendered} -> {:ok, Enum.reverse(rendered)}
      error -> error
    end
  end

  defp render_scene(%{narration: narration, slide_text: slide_text}, index, work_dir) do
    with {:ok, audio} <- narrator().synthesize(narration, []),
         {:ok, image} <- slide_renderer().render(slide_text, image: scene_illustration(narration)) do
      audio_path = Path.join(work_dir, "scene-#{index}.mp3")
      image_path = Path.join(work_dir, "scene-#{index}.png")

      with :ok <- File.write(audio_path, audio),
           :ok <- File.write(image_path, image) do
        {:ok, %{image_path: image_path, audio_path: audio_path}}
      end
    end
  end

  # A missing/failed illustration is never fatal to the whole generation —
  # the slide renderer already has a plain branded fallback for `nil`, so a
  # rate-limited or content-filtered scene just loses its background image,
  # not the video.
  defp scene_illustration(narration) do
    case image_generator().generate(narration, []) do
      {:ok, image} ->
        image

      {:error, reason} ->
        Logger.warning(
          "Overview scene illustration failed (#{inspect(reason)}); " <>
            "falling back to the plain branded slide for this scene."
        )

        nil
    end
  end

  defp storage_key(generation), do: "lecture-overviews/#{generation.id}.mp4"

  defp storage,
    do: Application.get_env(:wasomi, :catalog_storage, Wasomi.Catalog.Storage.R2)

  defp pdf_extractor,
    do: Application.get_env(:wasomi, :pdf_extractor, Wasomi.Assessments.PdfExtractor.PdfToText)

  defp script_generator,
    do:
      Application.get_env(
        :wasomi,
        :overview_script_generator,
        Wasomi.Catalog.OverviewScriptGenerator.OpenAI
      )

  defp narrator,
    do: Application.get_env(:wasomi, :overview_narrator, Wasomi.Catalog.OverviewNarrator.OpenAI)

  defp image_generator,
    do:
      Application.get_env(
        :wasomi,
        :overview_image_generator,
        Wasomi.Catalog.OverviewImageGenerator.OpenAI
      )

  defp slide_renderer,
    do: Application.get_env(:wasomi, :slide_renderer, Wasomi.Catalog.SlideRenderer.ChromicPdf)

  defp video_assembler,
    do: Application.get_env(:wasomi, :video_assembler, Wasomi.Catalog.VideoAssembler.Ffmpeg)

  defp link_text_fetcher,
    do: Application.get_env(:wasomi, :link_text_fetcher, Wasomi.Catalog.LinkTextFetcher.HttpFetch)
end
