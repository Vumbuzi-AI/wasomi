defmodule Wasomi.StorageTest do
  use Wasomi.DataCase
  alias Wasomi.Storage
  alias Wasomi.Storage.R2

  defmodule Adapter do
    def presign_upload(user, attrs), do: {:ok, %{user: user, attrs: attrs}}
  end

  test "only admins can request presigned uploads" do
    learner = Wasomi.AccountsFixtures.user_fixture()
    admin = Wasomi.AccountsFixtures.user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(admin, :admin)

    assert {:error, :forbidden} = Storage.presign_upload(learner, %{}, Adapter)

    assert {:ok, %{user: ^admin, attrs: %{filename: "notes.pdf"}}} =
             Storage.presign_upload(admin, %{filename: "notes.pdf"}, Adapter)
  end

  test "R2 rejects unsupported or oversized upload metadata" do
    assert {:error, :unsupported_content_type} =
             R2.presign_upload(nil, %{
               "filename" => "notes.zip",
               "content_type" => "application/zip",
               "size" => 100
             })

    assert {:error, :document_too_large} =
             R2.presign_upload(nil, %{
               "filename" => "notes.pdf",
               "content_type" => "application/pdf",
               "size" => 50_000_001
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
               "size" => 100
             })

    assert %URI{scheme: "https", host: "r2.example.test", path: "/test-bucket/" <> _} =
             URI.parse(url)
  end
end
