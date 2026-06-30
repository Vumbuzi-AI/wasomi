defmodule Wasomi.Media do
  @moduledoc """
  Server-side boundary for protected video delivery.

  Provider-specific upload and token generation belongs behind the configured
  adapter. Authorization always happens here first.
  """

  alias Wasomi.Accounts.User
  alias Wasomi.Catalog.Lecture
  alias Wasomi.Enrollments

  @type upload :: %{required(:id) => String.t(), required(:url) => String.t()}
  @type upload_status ::
          :waiting
          | :processing
          | {:ready, playback_id :: String.t(), duration_seconds :: pos_integer()}

  @callback create_upload(Lecture.t(), keyword()) :: {:ok, upload()} | {:error, term()}
  @callback upload_status(String.t()) :: {:ok, upload_status()} | {:error, term()}
  @callback playback_token(Lecture.t(), User.t(), pos_integer()) ::
              {:ok, String.t()} | {:error, term()}

  def playback_token(user, lecture, ttl \\ 300, adapter \\ configured_adapter()) do
    with {:ok, lecture} <- Enrollments.authorize_lecture(user, lecture) do
      adapter.playback_token(lecture, user, ttl)
    end
  end

  def playback_url(user, %Lecture{} = lecture, ttl \\ 300, adapter \\ configured_adapter()) do
    with {:ok, token} <- playback_token(user, lecture, ttl, adapter),
         {:ok, url} <- protected_stream_url(lecture, token) do
      {:ok, %{url: url, expires_in: effective_ttl(lecture, ttl)}}
    end
  end

  def create_upload(user, lecture, opts \\ [], adapter \\ configured_adapter())

  def create_upload(
        %User{role: :admin},
        %Lecture{} = lecture,
        opts,
        adapter
      ) do
    adapter.create_upload(lecture, opts)
  end

  def create_upload(_user, _lecture, _opts, _adapter), do: {:error, :forbidden}

  def upload_status(user, upload_id, adapter \\ configured_adapter())

  def upload_status(%User{role: :admin}, upload_id, adapter)
      when is_binary(upload_id) do
    adapter.upload_status(upload_id)
  end

  def upload_status(_user, _upload_id, _adapter), do: {:error, :forbidden}

  def effective_ttl(%Lecture{duration_seconds: duration}, requested_ttl)
      when is_integer(duration) and duration > 0 do
    max(requested_ttl, duration + 60)
  end

  def effective_ttl(_lecture, requested_ttl), do: requested_ttl

  def configured_adapter do
    Application.get_env(:wasomi, :media_provider, Wasomi.Media.Unconfigured)
  end

  # A locally uploaded file (served from priv/static/uploads) is streamed as-is.
  defp protected_stream_url(%Lecture{video_asset_id: "/uploads/" <> _ = path}, _token),
    do: {:ok, path}

  # A full HLS URL (e.g. seeded public sample) is streamed directly, no token.
  defp protected_stream_url(%Lecture{video_asset_id: "http" <> _ = url}, _token), do: {:ok, url}

  defp protected_stream_url(%Lecture{video_provider: :mux, video_asset_id: playback_id}, token)
       when is_binary(playback_id) and playback_id != "" do
    {:ok, "https://stream.mux.com/#{URI.encode(playback_id)}.m3u8?token=#{URI.encode(token)}"}
  end

  defp protected_stream_url(%Lecture{video_provider: provider}, _token),
    do: {:error, {:unsupported_video_provider, provider}}
end
