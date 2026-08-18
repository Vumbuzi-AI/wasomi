defmodule Wasomi.Media.Cloudflare do
  @moduledoc """
  Cloudflare Stream adapter for private HLS playback and direct uploads.

  `Lecture.video_asset_id` stores Cloudflare's video UID. Every created video
  requires signed URLs and is restricted to the configured Wasomi origin.
  """

  @behaviour Wasomi.Media

  alias Wasomi.Accounts.User
  alias Wasomi.Catalog.Lecture
  alias Wasomi.Media

  @impl true
  def create_upload(%Lecture{id: lecture_id}, opts) do
    origin = Keyword.get(opts, :cors_origin, configured_origin())

    request(:post, "/stream/direct_upload",
      json: %{
        maxDurationSeconds: 36_000,
        requireSignedURLs: true,
        allowedOrigins: allowed_origins(origin),
        meta: %{lecture_id: to_string(lecture_id)}
      }
    )
    |> case do
      {:ok, %{"uid" => uid, "uploadURL" => url}} -> {:ok, %{id: uid, url: url}}
      {:ok, body} -> {:error, {:unexpected_cloudflare_upload_response, body}}
      error -> error
    end
  end

  @impl true
  def upload_status(uid), do: video_status(uid)

  @impl true
  def playback_token(
        %Lecture{video_provider: :cloudflare, video_asset_id: uid} = lecture,
        %User{},
        requested_ttl
      )
      when is_binary(uid) and uid != "" do
    sign_token(uid, Media.effective_ttl(lecture, requested_ttl))
  end

  def playback_token(%Lecture{video_provider: provider}, _user, _ttl),
    do: {:error, {:unsupported_video_provider, provider}}

  @impl true
  def thumbnail_url(
        %Lecture{video_provider: :cloudflare, video_asset_id: uid} = lecture,
        %User{} = user
      )
      when is_binary(uid) and uid != "" do
    with {:ok, token} <- playback_token(lecture, user, 300) do
      {:ok, delivery_url(token, "/thumbnails/thumbnail.jpg")}
    end
  end

  def thumbnail_url(%Lecture{video_provider: provider}, _user),
    do: {:error, {:unsupported_video_provider, provider}}

  @impl true
  def download_url(%Lecture{video_provider: :cloudflare, video_asset_id: uid})
      when is_binary(uid) and uid != "" do
    # Creating a download is idempotent. The transcription job retries while
    # Cloudflare prepares the rendition, then receives a short-lived URL.
    with {:ok, _} <- request(:post, "/stream/#{URI.encode(uid)}/downloads/default"),
         {:ok, downloads} <- request(:get, "/stream/#{URI.encode(uid)}/downloads"),
         :ok <- download_ready(downloads),
         {:ok, token} <- sign_token(uid, 600, downloadable: true) do
      {:ok, delivery_url(token, "/downloads/default.mp4")}
    end
  end

  def download_url(%Lecture{video_provider: provider}),
    do: {:error, {:unsupported_video_provider, provider}}

  defp video_status(uid) when is_binary(uid) do
    with {:ok, video} <- request(:get, "/stream/#{URI.encode(uid)}") do
      resolve_video(video)
    end
  end

  defp resolve_video(%{"readyToStream" => true, "uid" => uid} = video) do
    maybe_generate_captions(uid)
    {:ok, {:ready, uid, ceil_duration(video["duration"])}}
  end

  defp resolve_video(%{"status" => %{"state" => state}})
       when state in ["queued", "downloading", "inprogress"] do
    {:ok, :processing}
  end

  defp resolve_video(%{"status" => %{"state" => "error"} = status}),
    do: {:error, {:cloudflare_video_errored, status}}

  defp resolve_video(other), do: {:error, {:unexpected_cloudflare_asset_response, other}}

  defp maybe_generate_captions(uid) do
    case request(:post, "/stream/#{URI.encode(uid)}/captions/en/generate") do
      {:ok, _} -> :ok
      # A caption already in progress/ready is harmless, and captions should
      # never hold an otherwise playable lecture hostage.
      {:error, _} -> :ok
    end
  end

  defp download_ready(%{"default" => %{"status" => "ready"}}), do: :ok
  defp download_ready(%{"status" => "ready"}), do: :ok
  defp download_ready(_), do: {:error, :cloudflare_download_processing}

  defp request(method, path, options \\ []) do
    Req.request(
      [
        method: method,
        url: api_url() <> "/client/v4/accounts/#{account_id()}" <> path,
        headers: [
          {"authorization", "Bearer " <> api_token()},
          {"content-type", "application/json"}
        ],
        retry: :transient,
        max_retries: 2,
        receive_timeout: 15_000
      ] ++ Application.get_env(:wasomi, :cloudflare_stream_req_options, []) ++ options
    )
    |> normalize_response()
  end

  defp normalize_response(
         {:ok, %{status: status, body: %{"success" => true, "result" => result}}}
       )
       when status in 200..299,
       do: {:ok, result}

  defp normalize_response({:ok, %{status: status, body: body}}),
    do: {:error, {:cloudflare, status, body}}

  defp normalize_response({:error, reason}), do: {:error, reason}

  defp sign_token(uid, ttl, extra_claims \\ []) do
    key_id = signing_key_id()
    header = %{"alg" => "RS256", "kid" => key_id}

    claims =
      %{kid: key_id, sub: uid, exp: System.system_time(:second) + min(ttl, 86_400)}
      |> Map.merge(Map.new(extra_claims))

    signing_input = encode_segment(header) <> "." <> encode_segment(claims)

    with {:ok, private_key} <- decode_private_key(),
         signature <- :public_key.sign(signing_input, :sha256, private_key) do
      {:ok, signing_input <> "." <> Base.url_encode64(signature, padding: false)}
    end
  rescue
    error -> {:error, {:invalid_cloudflare_signing_key, Exception.message(error)}}
  end

  defp decode_private_key do
    configured = signing_private_key()

    pem =
      case Base.decode64(configured),
        do: (
          {:ok, decoded} -> decoded
          :error -> configured
        )

    case :public_key.pem_decode(pem) do
      [entry | _] -> {:ok, :public_key.pem_entry_decode(entry)}
      [] -> {:error, :invalid_cloudflare_signing_key}
    end
  end

  defp encode_segment(value),
    do: value |> Jason.encode!() |> Base.url_encode64(padding: false)

  @doc false
  def delivery_url(token, suffix),
    do: "https://#{delivery_host()}/#{token}#{suffix}"

  defp delivery_host do
    customer_code()
    |> String.trim()
    |> String.trim_trailing("/")
    |> String.replace_prefix("https://", "")
    |> String.replace_prefix("http://", "")
    |> case do
      "customer-" <> _ = host -> host
      code -> "customer-#{code}.cloudflarestream.com"
    end
  end

  defp origin_host(origin), do: URI.parse(origin).host || origin

  # Cloudflare only accepts real domain names in `allowedOrigins`; local
  # development hosts and IP literals produce API error 10005. An empty list
  # permits any embedding origin, while `requireSignedURLs` still keeps the
  # video private. Production domains remain restricted to their host.
  defp allowed_origins(origin) do
    host = origin_host(origin)

    if host in ["localhost", "127.0.0.1", "::1"] or
         match?({:ok, _address}, :inet.parse_address(String.to_charlist(host))) do
      []
    else
      [host]
    end
  end

  defp ceil_duration(value) when is_number(value), do: value |> ceil() |> max(1)
  defp ceil_duration(_), do: 1

  defp api_url,
    do: Application.get_env(:wasomi, :cloudflare_api_url, "https://api.cloudflare.com")

  defp configured_origin,
    do: Application.get_env(:wasomi, :cloudflare_stream_origin, "http://localhost:4000")

  defp account_id, do: fetch_secret!(:cloudflare_account_id, "CLOUDFLARE_ACCOUNT_ID")
  defp api_token, do: fetch_secret!(:cloudflare_stream_api_token, "CLOUDFLARE_STREAM_API_TOKEN")

  defp customer_code,
    do: fetch_secret!(:cloudflare_stream_customer_code, "CLOUDFLARE_STREAM_CUSTOMER_CODE")

  defp signing_key_id,
    do: fetch_secret!(:cloudflare_stream_signing_key_id, "CLOUDFLARE_STREAM_SIGNING_KEY_ID")

  defp signing_private_key,
    do:
      fetch_secret!(
        :cloudflare_stream_signing_private_key,
        "CLOUDFLARE_STREAM_SIGNING_PRIVATE_KEY"
      )

  defp fetch_secret!(key, env_name),
    do: Application.get_env(:wasomi, key) || raise("#{env_name} is not configured")
end
