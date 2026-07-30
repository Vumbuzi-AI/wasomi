defmodule Wasomi.Assessments.Storage do
  @moduledoc """
  Private object storage boundary for the source PDFs behind quiz generation.

  Uploaded PDFs are kept out of the Oban job's `args` (a JSONB column) —
  large payloads there bloat the job table and slow polling — so a job
  carries only a storage key, and the worker downloads the bytes from here.
  """

  @callback upload(String.t(), binary()) :: :ok | {:error, term()}
  @callback download(String.t()) :: {:ok, binary()} | {:error, term()}
  @callback delete(String.t()) :: :ok | {:error, term()}
end
