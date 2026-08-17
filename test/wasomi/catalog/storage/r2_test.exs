defmodule Wasomi.Catalog.Storage.R2Test do
  use ExUnit.Case, async: false

  alias Wasomi.Catalog.Storage.R2

  defmodule CapturingHttpClient do
    def request(method, url, body, headers, _opts) do
      send(self(), {:http_request, method, url, body, headers})
      {:ok, %{status_code: 200, body: "", headers: []}}
    end
  end

  setup do
    previous = %{
      client: Application.get_env(:ex_aws, :http_client),
      bucket: Application.get_env(:wasomi, :r2_bucket),
      endpoint: Application.get_env(:wasomi, :r2_endpoint),
      access_key_id: Application.get_env(:ex_aws, :access_key_id),
      secret_access_key: Application.get_env(:ex_aws, :secret_access_key)
    }

    on_exit(fn ->
      Application.put_env(:ex_aws, :http_client, previous.client)
      Application.put_env(:wasomi, :r2_bucket, previous.bucket)
      Application.put_env(:wasomi, :r2_endpoint, previous.endpoint)
      Application.put_env(:ex_aws, :access_key_id, previous.access_key_id)
      Application.put_env(:ex_aws, :secret_access_key, previous.secret_access_key)
    end)

    Application.put_env(:ex_aws, :http_client, CapturingHttpClient)
    Application.put_env(:wasomi, :r2_bucket, "test-bucket")
    Application.put_env(:wasomi, :r2_endpoint, "https://r2.example.test")
    Application.put_env(:ex_aws, :access_key_id, "test-access-key")
    Application.put_env(:ex_aws, :secret_access_key, "test-secret-key")

    :ok
  end

  test "uploads a .vtt file as text/vtt, not the video content type" do
    assert :ok =
             R2.upload(
               "lecture-overviews/1.vtt",
               "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHi.\n"
             )

    assert_received {:http_request, :put, _url, _body, headers}
    assert {"content-type", "text/vtt"} in headers
  end

  test "uploads a .mp4 file as video/mp4" do
    assert :ok = R2.upload("lecture-overviews/1.mp4", "fake-mp4-bytes")

    assert_received {:http_request, :put, _url, _body, headers}
    assert {"content-type", "video/mp4"} in headers
  end

  test "falls back to a generic content type for an unrecognized extension" do
    assert :ok = R2.upload("lecture-overviews/1.bin", "raw-bytes")

    assert_received {:http_request, :put, _url, _body, headers}
    assert {"content-type", "application/octet-stream"} in headers
  end
end
