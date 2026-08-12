defmodule Wasomi.MediaTest do
  use Wasomi.DataCase

  import Mox
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures

  alias Wasomi.Media
  alias Wasomi.Media.Mux

  setup :verify_on_exit!

  describe "create_upload/4, upload_status/3, thumbnail_url/3 admin gating and forwarding" do
    test "create_upload/4 forwards (lecture, opts) to the adapter for an admin, unchanged" do
      lecture = lecture_fixture()
      admin = admin_fixture()

      expect(Wasomi.MediaProviderMock, :create_upload, fn ^lecture, [foo: :bar] ->
        {:ok, %{id: "upload-1", url: "https://storage.mux.test/direct-upload"}}
      end)

      assert {:ok, %{id: "upload-1"}} =
               Media.create_upload(admin, lecture, [foo: :bar], Wasomi.MediaProviderMock)
    end

    test "create_upload/4 never calls the adapter for a non-admin" do
      lecture = lecture_fixture()
      learner = user_fixture()

      assert {:error, :forbidden} =
               Media.create_upload(learner, lecture, [], Wasomi.MediaProviderMock)
    end

    test "upload_status/3 forwards the upload id to the adapter for an admin" do
      admin = admin_fixture()

      expect(Wasomi.MediaProviderMock, :upload_status, fn "upload-1" -> {:ok, :processing} end)

      assert {:ok, :processing} =
               Media.upload_status(admin, "upload-1", Wasomi.MediaProviderMock)
    end

    test "upload_status/3 never calls the adapter for a non-admin" do
      learner = user_fixture()

      assert {:error, :forbidden} =
               Media.upload_status(learner, "upload-1", Wasomi.MediaProviderMock)
    end

    test "thumbnail_url/3 forwards (lecture, user) to the adapter for an admin" do
      lecture = lecture_fixture()
      admin = admin_fixture()

      expect(Wasomi.MediaProviderMock, :thumbnail_url, fn ^lecture, ^admin ->
        {:ok, "https://image.mux.test/thumbnail.jpg"}
      end)

      assert {:ok, "https://image.mux.test/thumbnail.jpg"} =
               Media.thumbnail_url(admin, lecture, Wasomi.MediaProviderMock)
    end

    test "thumbnail_url/3 never calls the adapter for a non-admin" do
      lecture = lecture_fixture()
      learner = user_fixture()

      assert {:error, :forbidden} =
               Media.thumbnail_url(learner, lecture, Wasomi.MediaProviderMock)
    end
  end

  setup do
    private_key = :public_key.generate_key({:rsa, 1024, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private_key)])

    previous_key = Application.get_env(:wasomi, :mux_signing_private_key)
    previous_id = Application.get_env(:wasomi, :mux_signing_key_id)

    Application.put_env(:wasomi, :mux_signing_private_key, Base.encode64(pem))
    Application.put_env(:wasomi, :mux_signing_key_id, "test-key")

    on_exit(fn ->
      restore_env(:mux_signing_private_key, previous_key)
      restore_env(:mux_signing_key_id, previous_id)
    end)

    %{private_key: private_key}
  end

  test "Mux signs viewer-bound playback JWTs with enough lifetime for the lecture", %{
    private_key: private_key
  } do
    lecture =
      lecture_fixture(
        video_provider: :mux,
        video_asset_id: "signed-playback-id",
        duration_seconds: 900
      )

    user = user_fixture()
    other_user = user_fixture()
    issued_after = System.system_time(:second)

    assert {:ok, token} = Mux.playback_token(lecture, user, 300)
    assert {:ok, other_token} = Mux.playback_token(lecture, other_user, 300)
    refute token == other_token

    [header_segment, claims_segment, signature_segment] = String.split(token, ".")
    claims = claims_segment |> Base.url_decode64!(padding: false) |> Jason.decode!()
    header = header_segment |> Base.url_decode64!(padding: false) |> Jason.decode!()

    assert header == %{"alg" => "RS256", "typ" => "JWT"}
    assert claims["sub"] == "signed-playback-id"
    assert claims["aud"] == "v"
    assert claims["kid"] == "test-key"
    assert is_binary(claims["viewer_id"])
    assert claims["exp"] >= issued_after + 960

    signature = Base.url_decode64!(signature_segment, padding: false)
    public_key = {:RSAPublicKey, elem(private_key, 2), elem(private_key, 3)}

    assert :public_key.verify(
             header_segment <> "." <> claims_segment,
             :sha256,
             signature,
             public_key
           )
  end

  test "thumbnail_url/2 builds a URL where the playback id and signed token round-trip intact" do
    lecture =
      lecture_fixture(video_provider: :mux, video_asset_id: "av1Ab2_XyZ-9", duration_seconds: 120)

    user = user_fixture()

    assert {:ok, url} = Mux.thumbnail_url(lecture, user)
    assert String.starts_with?(url, "https://image.mux.com/av1Ab2_XyZ-9/thumbnail.jpg?token=")

    token = url |> String.split("token=") |> List.last()
    assert [_header, _claims, _signature] = String.split(token, ".")

    # playback_id is a path segment (URI.encode/1), token is a query value
    # (URI.encode_www_form/1) — assert each survives its actual encoder
    # unmangled for a real generated JWT, rather than assuming it.
    assert URI.encode_www_form(token) == token
    refute token =~ "%"
  end

  test "download_url/1 builds a signed static-rendition URL for the transcription pipeline" do
    lecture =
      lecture_fixture(video_provider: :mux, video_asset_id: "av1Ab2_XyZ-9", duration_seconds: 120)

    assert {:ok, url} = Mux.download_url(lecture)
    assert String.starts_with?(url, "https://stream.mux.com/av1Ab2_XyZ-9/low.mp4?token=")

    token = url |> String.split("token=") |> List.last()
    [header_segment, claims_segment, _signature_segment] = String.split(token, ".")
    claims = claims_segment |> Base.url_decode64!(padding: false) |> Jason.decode!()
    header = header_segment |> Base.url_decode64!(padding: false) |> Jason.decode!()

    assert header == %{"alg" => "RS256", "typ" => "JWT"}
    assert claims["sub"] == "av1Ab2_XyZ-9"
    assert claims["aud"] == "v"
  end

  test "download_url/1 rejects a non-Mux lecture" do
    lecture = lecture_fixture(video_provider: :cloudflare, video_asset_id: "some-id")
    assert {:error, {:unsupported_video_provider, :cloudflare}} = Mux.download_url(lecture)
  end

  defp restore_env(key, nil), do: Application.delete_env(:wasomi, key)
  defp restore_env(key, value), do: Application.put_env(:wasomi, key, value)

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end
end
