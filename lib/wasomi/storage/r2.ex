defmodule Wasomi.Storage.R2 do
  @behaviour Wasomi.Storage

  @allowed_types %{
    "application/pdf" => :document,
    "application/msword" => :document,
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => :document,
    "application/vnd.ms-powerpoint" => :document,
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" => :document,
    "application/zip" => :document,
    "application/x-zip-compressed" => :document,
    "text/plain" => :document,
    "video/mp4" => :video,
    "video/quicktime" => :video,
    "video/webm" => :video,
    "image/png" => :image
  }

  @max_document_bytes 50_000_000
  @max_video_bytes 1_000_000_000
  @max_image_bytes 2_000_000

  @impl true
  def presign_upload(_user, attrs) do
    filename = Map.get(attrs, "filename") || Map.get(attrs, :filename)

    content_type =
      attrs
      |> then(&(Map.get(&1, "content_type") || Map.get(&1, :content_type)))
      |> normalize_content_type(filename)

    byte_size = Map.get(attrs, "size") || Map.get(attrs, :size)

    with {:ok, kind} <- validate_metadata(filename, content_type, byte_size),
         {:ok, bucket} <- bucket(),
         {:ok, endpoint} <- endpoint(),
         {:ok, byte_size} <- normalize_size(byte_size) do
      key = upload_key(attrs, filename)

      config =
        ExAws.Config.new(:s3, host: endpoint.host, port: endpoint.port, scheme: endpoint.scheme)

      with {:ok, url} <-
             ExAws.S3.presigned_url(config, :put, bucket, key,
               expires_in: upload_expiry(),
               query_params: [{"content-type", content_type}]
             ) do
        {:ok,
         %{
           key: key,
           url: url,
           public_url: public_url(key),
           expires_in: upload_expiry(),
           kind: kind,
           content_type: content_type,
           byte_size: byte_size
         }}
      end
    end
  end

  defp upload_key(attrs, filename) do
    prefix =
      attrs
      |> Map.get("prefix", Map.get(attrs, :prefix, "draft-#{Ecto.UUID.generate()}"))
      |> to_string()
      |> String.replace(~r/[^A-Za-z0-9_-]/, "_")

    "lectures/#{prefix}/#{Ecto.UUID.generate()}/#{safe_filename(filename)}"
  end

  @impl true
  def delete_upload(_user, key) when is_binary(key) and key != "" do
    with {:ok, bucket} <- bucket(),
         {:ok, endpoint} <- endpoint() do
      config =
        ExAws.Config.new(:s3, host: endpoint.host, port: endpoint.port, scheme: endpoint.scheme)

      case ExAws.S3.delete_object(bucket, key) |> ExAws.request(config) do
        {:ok, %{status_code: code}} when code >= 200 and code < 300 -> :ok
        {:ok, %{status_code: code, body: body}} -> {:error, {:http_error, code, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def delete_upload(_user, _key), do: {:error, :invalid_storage_key}

  defp validate_metadata(filename, content_type, byte_size)
       when is_binary(filename) and filename != "" and is_binary(content_type) do
    with {:ok, kind} <- Map.fetch(@allowed_types, content_type),
         {:ok, byte_size} <- normalize_size(byte_size),
         :ok <- validate_size(kind, byte_size) do
      {:ok, kind}
    else
      :error -> {:error, :unsupported_content_type}
      {:error, _} = error -> error
    end
  end

  defp validate_metadata(_, _, _), do: {:error, :invalid_upload_metadata}

  defp normalize_content_type(content_type, _filename)
       when is_binary(content_type) and content_type not in ["", "application/octet-stream"],
       do: content_type

  defp normalize_content_type(_content_type, filename) when is_binary(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".pdf" -> "application/pdf"
      ".doc" -> "application/msword"
      ".docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      ".ppt" -> "application/vnd.ms-powerpoint"
      ".pptx" -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      ".zip" -> "application/zip"
      ".txt" -> "text/plain"
      ".mp4" -> "video/mp4"
      ".mov" -> "video/quicktime"
      ".webm" -> "video/webm"
      ".png" -> "image/png"
      _ -> "application/octet-stream"
    end
  end

  defp normalize_content_type(content_type, _filename), do: content_type

  defp normalize_size(size) when is_integer(size) and size > 0, do: {:ok, size}

  defp normalize_size(size) when is_binary(size) do
    case Integer.parse(size) do
      {size, ""} when size > 0 -> {:ok, size}
      _ -> {:error, :invalid_file_size}
    end
  end

  defp normalize_size(_), do: {:error, :invalid_file_size}

  defp validate_size(:document, size) when size <= @max_document_bytes, do: :ok
  defp validate_size(:video, size) when size <= @max_video_bytes, do: :ok
  defp validate_size(:image, size) when size <= @max_image_bytes, do: :ok
  defp validate_size(:document, _), do: {:error, :document_too_large}
  defp validate_size(:video, _), do: {:error, :video_too_large}
  defp validate_size(:image, _), do: {:error, :image_too_large}

  defp safe_filename(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[^A-Za-z0-9._-]/, "_")
  end

  defp bucket do
    case Application.get_env(:wasomi, :r2_bucket) do
      bucket when is_binary(bucket) and bucket != "" -> {:ok, bucket}
      _ -> {:error, :r2_not_configured}
    end
  end

  defp endpoint do
    case Application.get_env(:wasomi, :r2_endpoint) do
      endpoint when is_binary(endpoint) ->
        case URI.parse(endpoint) do
          %URI{scheme: scheme, host: host} = uri
          when scheme in ["http", "https"] and is_binary(host) ->
            # ExAws.S3 expects the scheme with its trailing `://`.
            {:ok, %{scheme: "#{scheme}://", host: host, port: uri.port}}

          _ ->
            {:error, :r2_not_configured}
        end

      _ ->
        {:error, :r2_not_configured}
    end
  end

  @impl true
  def download_url(key) do
    case public_url(key) do
      nil -> {:error, :r2_not_configured}
      url -> {:ok, url}
    end
  end

  defp public_url(key) do
    case Application.get_env(:wasomi, :r2_public_url) do
      base when is_binary(base) and base != "" ->
        String.trim_trailing(base, "/") <> "/" <> key

      _ ->
        nil
    end
  end

  defp upload_expiry do
    case Application.get_env(:wasomi, :r2_upload_expiry, 900) do
      value when is_integer(value) and value > 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {value, ""} when value > 0 -> value
          _ -> 900
        end

      _ ->
        900
    end
  end
end
