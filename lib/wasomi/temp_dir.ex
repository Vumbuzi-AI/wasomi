defmodule Wasomi.TempDir do
  @moduledoc """
  Scratch-directory helper for workers that need to write intermediate
  files to disk (e.g. `Wasomi.Catalog.Workers.GenerateLectureOverviewWorker`'s
  per-scene audio/image files before `ffmpeg` assembly) — creates a unique
  directory under `System.tmp_dir!/0`, always removes it afterward
  regardless of success, failure, or a raised exception.
  """

  @doc """
  Runs `fun` with the path to a freshly created, empty temp directory,
  removing the directory (and everything written into it) before
  returning — the caller's result is passed through unchanged.
  """
  @spec with_tmp_dir((Path.t() -> result)) :: result when result: term()
  def with_tmp_dir(fun) when is_function(fun, 1) do
    dir = Path.join(System.tmp_dir!(), "wasomi-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      fun.(dir)
    after
      File.rm_rf!(dir)
    end
  end
end
