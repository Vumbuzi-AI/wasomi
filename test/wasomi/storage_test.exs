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
end
