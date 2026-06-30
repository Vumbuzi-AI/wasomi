defmodule Wasomi.Media.Mux do
  @moduledoc """
  Mux Video adapter for signed playback and browser-to-Mux direct uploads.

  `Lecture.video_asset_id` stores the signed Mux playback ID used for HLS
  delivery, not an asset URL or an MP4 URL.
  """

  @behaviour Wasomi.Media

  alias Wasomi.Accounts.User
  alias Wasomi.Catalog.Lecture
  alias Wasomi.Media

  @api_path "/video/v1"

  @impl true
  def create_upload(%Lecture{id: lecture_id}, opts) do
    cors_origin = Keyword.get(opts, :cors_origin, configured_cors_origin())

    request(:post, "/uploads",
      json: %{
        cors_origin: cors_origin,
        new_asset_settings: %{
          passthrough: "lecture:#{lecture_id}",
          playback_policies: ["signed"],
          video_quality: "basic"
        }
      }
    )
    |> case do
      {:ok, %{"id" => id, "url" => url}} -> {:ok, %{id: id, url: url}}
      {:ok, body} -> {:error, {:unexpected_mux_upload_response, body}}
      error -> error
    end
  end

  @impl true
  def upload_status(upload_id) when is_binary(upload_id) do
    with {:ok, upload} <- request(:get, "/uploads/#{URI.encode(upload_id)}") do
      resolve_upload(upload)
    end
  end

  @impl true
  def playback_token(
        %Lecture{video_provider: :mux, video_asset_id: playback_id} = lecture,
        %User{} = user,
        requested_ttl
      )
      when is_binary(playback_id) and playback_id != "" do
    now = System.system_time(:second)

    claims = %{
      "sub" => playback_id,
      "aud" => "v",
      "exp" => now + Media.effective_ttl(lecture, requested_ttl),
      "kid" => signing_key_id(),
      "viewer_id" => viewer_id(user)
    }

    sign_jwt(claims)
  end

  def playback_token(%Lecture{video_provider: provider}, _user, _ttl),
    do: {:error, {:unsupported_video_provider, provider}}

  defp resolve_upload(%{"asset_id" => asset_id}) when is_binary(asset_id) do
    with {:ok, asset} <- request(:get, "/assets/#{URI.encode(asset_id)}") do
      case asset do
        %{"status" => "ready", "playback_ids" => playback_ids} when is_list(playback_ids) ->
          case Enum.find(playback_ids, &(&1["policy"] == "signed")) do
            %{"id" => playback_id} ->
              duration =
                asset
                |> Map.get("duration", 1)
                |> ceil_duration()

              {:ok, {:ready, playback_id, duration}}

            nil ->
              {:error, :mux_asset_has_no_signed_playback_id}
          end

        %{"status" => status} when status in ["preparing", "created"] ->
          {:ok, :processing}

        %{"status" => "errored", "errors" => errors} ->
          {:error, {:mux_asset_errored, errors}}

        other ->
          {:error, {:unexpected_mux_asset_response, other}}
      end
    end
  end

  defp resolve_upload(%{"status" => status}) when status in ["waiting", "asset_created"],
    do: {:ok, :waiting}

  defp resolve_upload(%{"status" => "errored", "error" => error}),
    do: {:error, {:mux_upload_errored, error}}

  defp resolve_upload(other), do: {:error, {:unexpected_mux_upload_response, other}}

  defp request(method, path, options \\ []) do
    Req.request(
      [
        method: method,
        url: api_url() <> @api_path <> path,
        headers: [
          {"authorization", "Basic " <> Base.encode64("#{token_id()}:#{token_secret()}")},
          {"content-type", "application/json"}
        ],
        retry: :transient,
        max_retries: 2,
        receive_timeout: 15_000
      ] ++ options
    )
    |> normalize_response()
  end

  defp normalize_response({:ok, %{status: status, body: %{"data" => data}}})
       when status in 200..299,
       do: {:ok, data}

  defp normalize_response({:ok, %{body: %{"error" => error}}}), do: {:error, {:mux, error}}

  defp normalize_response({:ok, %{status: status, body: body}}),
    do: {:error, {:mux, status, body}}

  defp normalize_response({:error, reason}), do: {:error, reason}

  defp sign_jwt(claims) do
    header = %{"alg" => "RS256", "typ" => "JWT"}
    signing_input = encode_segment(header) <> "." <> encode_segment(claims)

    with {:ok, private_key} <- decode_private_key(),
         signature <- :public_key.sign(signing_input, :sha256, private_key) do
      {:ok, signing_input <> "." <> Base.url_encode64(signature, padding: false)}
    end
  rescue
    error -> {:error, {:invalid_mux_signing_key, Exception.message(error)}}
  end

  defp decode_private_key do
    configured_key = signing_private_key()

    pem =
      case Base.decode64(configured_key) do
        {:ok, decoded} -> decoded
        :error -> configured_key
      end

    case :public_key.pem_decode(pem) do
      [entry | _] -> {:ok, :public_key.pem_entry_decode(entry)}
      [] -> {:error, :invalid_mux_signing_key}
    end
  end

  defp encode_segment(value) do
    value
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  defp viewer_id(%User{id: id, email: email}) do
    :crypto.hash(:sha256, "#{id}:#{String.downcase(email)}")
    |> Base.url_encode64(padding: false)
  end

  defp ceil_duration(duration) when is_float(duration),
    do: duration |> Float.ceil() |> trunc() |> max(1)

  defp ceil_duration(duration) when is_integer(duration), do: max(duration, 1)
  defp ceil_duration(_duration), do: 1

  defp api_url, do: Application.get_env(:wasomi, :mux_api_url, "https://api.mux.com")

  defp configured_cors_origin do
    Application.get_env(:wasomi, :mux_cors_origin, "http://localhost:4000")
  end

  defp token_id, do: fetch_secret!(:mux_token_id, "MUX_TOKEN_ID")
  defp token_secret, do: fetch_secret!(:mux_token_secret, "MUX_TOKEN_SECRET")
  defp signing_key_id, do: fetch_secret!(:mux_signing_key_id, "MUX_SIGNING_KEY_ID")

  defp signing_private_key,
    do: fetch_secret!(:mux_signing_private_key, "MUX_SIGNING_PRIVATE_KEY")

  defp fetch_secret!(key, env_name) do
    Application.get_env(:wasomi, key) ||
      raise "#{env_name} is not configured"
  end
end
