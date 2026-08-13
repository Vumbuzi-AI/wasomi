defmodule Wasomi.Catalog.VideoAssembler.Ffmpeg do
  @moduledoc """
  Assembles scenes into a single MP4 via `ffmpeg` — each scene becomes a
  clip held for the length of its narration audio (a static frame, see
  `render_clip/3` — an earlier "Ken Burns" pan/zoom version of this looked
  worse in practice than a plain still, not better, so it was removed),
  scenes are concatenated in order, and a fixed Wasomi watermark is burned
  into the assembled result (see `concatenate/2`).

  Not a Hex package dependency, the same operational shape as
  `Wasomi.Certificates.Renderer.ChromicPdf` requiring a Chrome executable
  (see `Wasomi.Application`): `ffmpeg` must be present on the host.
  """

  @behaviour Wasomi.Catalog.VideoAssembler

  require Logger

  @impl true
  def assemble(scenes, output_path) when is_list(scenes) and scenes != [] do
    with {:ok, ffmpeg} <- ffmpeg_executable(),
         work_dir <- Path.dirname(output_path),
         {:ok, clip_paths} <- render_clips(ffmpeg, scenes, work_dir),
         {:ok, concat_list} <- write_concat_list(clip_paths, work_dir) do
      concatenate(ffmpeg, concat_list, output_path)
    end
  end

  defp render_clips(ffmpeg, scenes, work_dir) do
    scenes
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {scene, index}, {:ok, acc} ->
      clip_path = Path.join(work_dir, "scene-#{index}.mp4")

      case render_clip(ffmpeg, scene, clip_path) do
        :ok -> {:cont, {:ok, [clip_path | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, paths} -> {:ok, Enum.reverse(paths)}
      error -> error
    end
  end

  defp render_clip(ffmpeg, %{image_path: image_path, audio_path: audio_path}, clip_path) do
    run(ffmpeg, static_args(image_path, audio_path, clip_path))
  end

  defp static_args(image_path, audio_path, clip_path) do
    [
      "-y",
      "-loop",
      "1",
      "-i",
      image_path,
      "-i",
      audio_path,
      "-c:v",
      "libx264",
      "-tune",
      "stillimage",
      "-c:a",
      "aac",
      "-b:a",
      "192k",
      "-pix_fmt",
      "yuv420p",
      "-shortest",
      clip_path
    ]
  end

  defp write_concat_list(clip_paths, work_dir) do
    list_path = Path.join(work_dir, "concat.txt")

    contents = Enum.map_join(clip_paths, "\n", fn path -> "file '#{Path.expand(path)}'" end)

    case File.write(list_path, contents) do
      :ok -> {:ok, list_path}
      {:error, reason} -> {:error, {:concat_list_write_failed, reason}}
    end
  end

  # Not a stream copy (each scene clip's own encode) — the watermark below
  # is a video filter, which forces a decode/filter/re-encode pass
  # regardless, so it's applied here in the same pass rather than adding a
  # second full re-encode afterward.
  defp concatenate(ffmpeg, concat_list, output_path) do
    with :ok <-
           run(ffmpeg, [
             "-y",
             "-f",
             "concat",
             "-safe",
             "0",
             "-i",
             concat_list,
             "-vf",
             watermark_filter(),
             "-c:v",
             "libx264",
             "-c:a",
             "aac",
             "-b:a",
             "192k",
             "-pix_fmt",
             "yuv420p",
             output_path
           ]) do
      {:ok, output_path}
    end
  end

  # Burned into the final assembled video, not each scene's source image —
  # a corner mark baked into a still that then gets panned/zoomed (the
  # earlier approach) drifts out of the crop entirely partway through the
  # animation. Applied once here, it stays fixed on screen for the whole
  # video regardless of what any individual scene is doing underneath.
  # `font=` (fontconfig lookup, this host has `--enable-libfontconfig`)
  # rather than a hardcoded `fontfile=` path, so it doesn't depend on a
  # specific font file existing at a specific path on the host.
  defp watermark_filter do
    "drawtext=text='WASOMI':font=DejaVu Sans Bold:fontcolor=white@0.55:fontsize=20:" <>
      "box=1:boxcolor=black@0.4:boxborderw=10:x=w-tw-32:y=h-th-28"
  end

  defp run(ffmpeg, args) do
    case System.cmd(ffmpeg, args, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, exit_code} ->
        Logger.error("ffmpeg exited #{exit_code}: #{output}")
        {:error, {:ffmpeg_failed, exit_code}}
    end
  end

  defp ffmpeg_executable do
    case System.find_executable("ffmpeg") do
      nil -> {:error, :ffmpeg_not_found}
      path -> {:ok, path}
    end
  end
end
