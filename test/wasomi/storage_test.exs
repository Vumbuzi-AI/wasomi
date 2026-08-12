defmodule Wasomi.StorageTest do
  use Wasomi.DataCase
  alias Wasomi.Storage
  alias Wasomi.Storage.R2

  defmodule Adapter do
    def presign_upload(user, attrs), do: {:ok, %{user: user, attrs: attrs}}
    def delete_upload(user, key), do: {:ok, {user, key}}
  end

  test "only admins can request presigned uploads" do
    learner = Wasomi.AccountsFixtures.user_fixture()
    admin = Wasomi.AccountsFixtures.user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(admin, :admin)

    assert {:error, :forbidden} = Storage.presign_upload(learner, %{}, Adapter)

    assert {:ok, %{user: ^admin, attrs: %{filename: "notes.pdf"}}} =
             Storage.presign_upload(admin, %{filename: "notes.pdf"}, Adapter)
  end

  test "presign_upload/2 reads the configured adapter at runtime" do
    previous = Application.get_env(:wasomi, :storage_provider)
    on_exit(fn -> Application.put_env(:wasomi, :storage_provider, previous) end)
    Application.put_env(:wasomi, :storage_provider, Adapter)

    admin = Wasomi.AccountsFixtures.user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(admin, :admin)

    assert {:ok, %{user: ^admin, attrs: %{filename: "notes.pdf"}}} =
             Storage.presign_upload(admin, %{filename: "notes.pdf"})
  end

  test "R2 rejects unsupported or oversized upload metadata" do
    assert {:error, :unsupported_content_type} =
             R2.presign_upload(nil, %{
               "filename" => "notes.exe",
               "content_type" => "application/x-msdownload",
               "size" => 100
             })

    assert {:error, :document_too_large} =
             R2.presign_upload(nil, %{
               "filename" => "notes.pdf",
               "content_type" => "application/pdf",
               "size" => 50_000_001
             })

    assert {:error, :document_too_large} =
             R2.presign_upload(nil, %{
               "filename" => "archive.zip",
               "content_type" => "application/zip",
               "size" => 50_000_001
             })

    assert {:error, :image_too_large} =
             R2.presign_upload(nil, %{
               "filename" => "signature.png",
               "content_type" => "image/png",
               "size" => 2_000_001
             })
  end

  test "R2 accepts a PNG upload within the size limit" do
    previous_bucket = Application.get_env(:wasomi, :r2_bucket)
    previous_endpoint = Application.get_env(:wasomi, :r2_endpoint)
    previous_access = Application.get_env(:ex_aws, :access_key_id)
    previous_secret = Application.get_env(:ex_aws, :secret_access_key)

    on_exit(fn ->
      Application.put_env(:wasomi, :r2_bucket, previous_bucket)
      Application.put_env(:wasomi, :r2_endpoint, previous_endpoint)
      Application.put_env(:ex_aws, :access_key_id, previous_access)
      Application.put_env(:ex_aws, :secret_access_key, previous_secret)
    end)

    Application.put_env(:wasomi, :r2_bucket, "test-bucket")
    Application.put_env(:wasomi, :r2_endpoint, "https://r2.example.test")
    Application.put_env(:ex_aws, :access_key_id, "test-access-key")
    Application.put_env(:ex_aws, :secret_access_key, "test-secret-key")

    assert {:ok, %{kind: :image, content_type: "image/png"}} =
             R2.presign_upload(nil, %{
               "filename" => "signature.png",
               "content_type" => "image/png",
               "size" => 1_000
             })
  end

  test "R2 presigned URLs use the configured endpoint scheme" do
    previous = %{
      bucket: Application.get_env(:wasomi, :r2_bucket),
      endpoint: Application.get_env(:wasomi, :r2_endpoint),
      public_url: Application.get_env(:wasomi, :r2_public_url),
      access_key_id: Application.get_env(:ex_aws, :access_key_id),
      secret_access_key: Application.get_env(:ex_aws, :secret_access_key)
    }

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        app = if key in [:access_key_id, :secret_access_key], do: :ex_aws, else: :wasomi
        app_key = if app == :ex_aws, do: key, else: :"r2_#{key}"
        Application.put_env(app, app_key, value)
      end)
    end)

    Application.put_env(:wasomi, :r2_bucket, "test-bucket")
    Application.put_env(:wasomi, :r2_endpoint, "https://r2.example.test")
    Application.put_env(:wasomi, :r2_public_url, "https://cdn.example.test")
    Application.put_env(:ex_aws, :access_key_id, "test-access-key")
    Application.put_env(:ex_aws, :secret_access_key, "test-secret-key")

    assert {:ok, %{url: url}} =
             R2.presign_upload(nil, %{
               "filename" => "notes.pdf",
               "content_type" => "application/pdf",
               "size" => 100,
               "prefix" => "lecture-42"
             })

    assert %URI{scheme: "https", host: "r2.example.test", path: "/test-bucket/" <> _} =
             URI.parse(url)

    assert URI.parse(url).path =~
             ~r"/test-bucket/lectures/lecture-42/[a-f0-9\-]+/notes\.pdf$"
  end

  test "R2 presigned uploads return nil public_url without a public base" do
    previous = %{
      bucket: Application.get_env(:wasomi, :r2_bucket),
      endpoint: Application.get_env(:wasomi, :r2_endpoint),
      public_url: Application.get_env(:wasomi, :r2_public_url),
      access_key_id: Application.get_env(:ex_aws, :access_key_id),
      secret_access_key: Application.get_env(:ex_aws, :secret_access_key)
    }

    on_exit(fn ->
      Application.put_env(:wasomi, :r2_bucket, previous.bucket)
      Application.put_env(:wasomi, :r2_endpoint, previous.endpoint)
      Application.put_env(:wasomi, :r2_public_url, previous.public_url)
      Application.put_env(:ex_aws, :access_key_id, previous.access_key_id)
      Application.put_env(:ex_aws, :secret_access_key, previous.secret_access_key)
    end)

    Application.put_env(:wasomi, :r2_bucket, "test-bucket")
    Application.put_env(:wasomi, :r2_endpoint, "https://r2.example.test")
    Application.delete_env(:wasomi, :r2_public_url)
    Application.put_env(:ex_aws, :access_key_id, "test-access-key")
    Application.put_env(:ex_aws, :secret_access_key, "test-secret-key")

    assert {:ok, %{public_url: nil}} =
             R2.presign_upload(nil, %{
               "filename" => "notes.pdf",
               "content_type" => "application/pdf",
               "size" => 100
             })
  end

  test "R2.download_url/1 recomputes a public URL from the configured base" do
    previous = Application.get_env(:wasomi, :r2_public_url)
    on_exit(fn -> Application.put_env(:wasomi, :r2_public_url, previous) end)
    Application.put_env(:wasomi, :r2_public_url, "https://cdn.example.test")

    assert {:ok, "https://cdn.example.test/lectures/123/notes.pdf"} =
             R2.download_url("lectures/123/notes.pdf")
  end

  test "R2.download_url/1 errors instead of returning a broken URL when unconfigured" do
    previous = Application.get_env(:wasomi, :r2_public_url)
    on_exit(fn -> Application.put_env(:wasomi, :r2_public_url, previous) end)
    Application.delete_env(:wasomi, :r2_public_url)

    assert {:error, :r2_not_configured} = R2.download_url("lectures/123/notes.pdf")
  end

  test "Storage.download_url/2 rejects a blank storage key" do
    assert {:error, :invalid_storage_key} = Storage.download_url("", Adapter)
    assert {:error, :invalid_storage_key} = Storage.download_url(nil, Adapter)
  end

  test "only admins can delete uploads" do
    learner = Wasomi.AccountsFixtures.user_fixture()
    admin = Wasomi.AccountsFixtures.user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(admin, :admin)

    assert {:error, :forbidden} = Storage.delete_upload(learner, "key.pdf", Adapter)
    assert {:ok, {^admin, "key.pdf"}} = Storage.delete_upload(admin, "key.pdf", Adapter)
  end

  test "delete_upload/2 reads the configured adapter at runtime" do
    previous = Application.get_env(:wasomi, :storage_provider)
    on_exit(fn -> Application.put_env(:wasomi, :storage_provider, previous) end)
    Application.put_env(:wasomi, :storage_provider, Adapter)

    admin = Wasomi.AccountsFixtures.user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(admin, :admin)

    assert {:ok, {^admin, "key.pdf"}} = Storage.delete_upload(admin, "key.pdf")
  end

  defmodule MockExAwsHttpClient do
    def request(method, url, body, headers, _opts) do
      send(self(), {:http_request, method, url, body, headers})
      {:ok, %{status_code: 200, body: "", headers: []}}
    end
  end

  test "R2.delete_upload/2 issues a delete request to S3" do
    previous_client = Application.get_env(:ex_aws, :http_client)
    previous_bucket = Application.get_env(:wasomi, :r2_bucket)
    previous_endpoint = Application.get_env(:wasomi, :r2_endpoint)
    previous_access = Application.get_env(:ex_aws, :access_key_id)
    previous_secret = Application.get_env(:ex_aws, :secret_access_key)

    on_exit(fn ->
      Application.put_env(:ex_aws, :http_client, previous_client)
      Application.put_env(:wasomi, :r2_bucket, previous_bucket)
      Application.put_env(:wasomi, :r2_endpoint, previous_endpoint)
      Application.put_env(:ex_aws, :access_key_id, previous_access)
      Application.put_env(:ex_aws, :secret_access_key, previous_secret)
    end)

    Application.put_env(:ex_aws, :http_client, MockExAwsHttpClient)
    Application.put_env(:wasomi, :r2_bucket, "test-bucket")
    Application.put_env(:wasomi, :r2_endpoint, "https://r2.example.test")
    Application.put_env(:ex_aws, :access_key_id, "test-access-key")
    Application.put_env(:ex_aws, :secret_access_key, "test-secret-key")

    assert :ok = R2.delete_upload(nil, "lectures/123/notes.pdf")

    assert_received {:http_request, :delete, url, _, _}
    assert url =~ "lectures/123/notes.pdf"
  end

  test "R2.delete_upload/2 handles ExAws request errors" do
    defmodule ErrorHttpClient do
      def request(_method, _url, _body, _headers, _opts) do
        {:ok, %{status_code: 404, body: "Not Found", headers: []}}
      end
    end

    previous_client = Application.get_env(:ex_aws, :http_client)
    previous_bucket = Application.get_env(:wasomi, :r2_bucket)
    previous_endpoint = Application.get_env(:wasomi, :r2_endpoint)
    previous_access = Application.get_env(:ex_aws, :access_key_id)
    previous_secret = Application.get_env(:ex_aws, :secret_access_key)

    on_exit(fn ->
      Application.put_env(:ex_aws, :http_client, previous_client)
      Application.put_env(:wasomi, :r2_bucket, previous_bucket)
      Application.put_env(:wasomi, :r2_endpoint, previous_endpoint)
      Application.put_env(:ex_aws, :access_key_id, previous_access)
      Application.put_env(:ex_aws, :secret_access_key, previous_secret)
    end)

    Application.put_env(:ex_aws, :http_client, ErrorHttpClient)
    Application.put_env(:wasomi, :r2_bucket, "test-bucket")
    Application.put_env(:wasomi, :r2_endpoint, "https://r2.example.test")
    Application.put_env(:ex_aws, :access_key_id, "test-access-key")
    Application.put_env(:ex_aws, :secret_access_key, "test-secret-key")

    assert {:error, {:http_error, 404, _body}} =
             R2.delete_upload(nil, "lectures/123/notes.pdf")
  end
end
