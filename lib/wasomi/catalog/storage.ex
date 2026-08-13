defmodule Wasomi.Catalog.Storage do
  @moduledoc """
  Private object storage boundary for generated lecture-overview output —
  the assembled video and its WebVTT captions track — same shape as
  `Wasomi.Assessments.Storage`, a separate boundary because this module
  tree has no other reason to depend on Assessments.
  """

  @callback upload(String.t(), binary()) :: :ok | {:error, term()}
  @callback download(String.t()) :: {:ok, binary()} | {:error, term()}
  @callback delete(String.t()) :: :ok | {:error, term()}

  @doc """
  A public URL an admin's browser can play a generated video from directly
  (a plain `<video>` tag, not a signed/protected stream like real lecture
  playback) — same `R2_PUBLIC_URL`-based scheme as `Wasomi.Storage.R2`'s
  `download_url/1`, just scoped to this module's own adapter config.
  """
  @callback download_url(String.t()) :: {:ok, String.t()} | {:error, term()}
end
