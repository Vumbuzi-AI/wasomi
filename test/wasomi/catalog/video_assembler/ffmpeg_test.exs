defmodule Wasomi.Catalog.VideoAssembler.FfmpegTest do
  use ExUnit.Case, async: true

  alias Wasomi.Catalog.VideoAssembler.Ffmpeg

  # Unlike the ChromicPDF adapters (which control availability deliberately
  # via config/test.exs's start_chromic_pdf: false, independent of what's
  # actually installed on the host), ffmpeg is invoked directly via
  # System.cmd/3 with no supervised process to toggle off — so this test
  # branches on whatever's actually on the running machine instead of
  # assuming it's absent, to avoid breaking in a CI/dev image that does
  # have ffmpeg installed.
  test "fails without crashing whether or not ffmpeg is installed on this host" do
    scenes = [%{image_path: "/tmp/does-not-exist.png", audio_path: "/tmp/does-not-exist.mp3"}]

    case System.find_executable("ffmpeg") do
      nil ->
        assert {:error, :ffmpeg_not_found} = Ffmpeg.assemble(scenes, "/tmp/output.mp4")

      _path ->
        # ffmpeg is present but the scene files above don't exist, so this
        # exercises the "ffmpeg ran and failed" path instead.
        assert {:error, {:ffmpeg_failed, _exit_code}} =
                 Ffmpeg.assemble(scenes, "/tmp/output.mp4")
    end
  end
end
