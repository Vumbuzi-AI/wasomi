defmodule Wasomi.Assessments.Storage.Local do
  @moduledoc """
  Disk-backed adapter used in dev, so quiz generation works locally without
  real R2 credentials (see `config/dev.exs`; same idea as `Wasomi.Media.Demo`
  standing in for Mux).
  """

  @behaviour Wasomi.Assessments.Storage

  @dir Path.join(System.tmp_dir!(), "wasomi-assessments-storage")

  @impl true
  def upload(key, pdf) when is_binary(key) and is_binary(pdf) do
    path = path_for(key)
    File.mkdir_p!(Path.dirname(path))
    File.write(path, pdf)
  end

  @impl true
  def download(key) when is_binary(key), do: File.read(path_for(key))

  @impl true
  def delete(key) when is_binary(key) do
    case File.rm(path_for(key)) do
      {:error, :enoent} -> :ok
      result -> result
    end
  end

  defp path_for(key), do: Path.join(@dir, key)
end
