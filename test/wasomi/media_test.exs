defmodule Wasomi.MediaTest do
  use Wasomi.DataCase

  import Mox
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures

  alias Wasomi.Media
  alias Wasomi.Media.Cloudflare

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

  describe "Cloudflare Stream API adapter" do
    test "creates a private direct upload restricted to the configured origin" do
      lecture = lecture_fixture()

      Req.Test.stub(Cloudflare, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/client/v4/accounts/test-account-id/stream/direct_upload"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["requireSignedURLs"]
        assert payload["allowedOrigins"] == []
        assert payload["meta"] == %{"lecture_id" => to_string(lecture.id)}

        Req.Test.json(conn, %{
          success: true,
          result: %{uid: "video-123", uploadURL: "https://upload.example.test/once"}
        })
      end)

      assert {:ok, %{id: "video-123", url: "https://upload.example.test/once"}} =
               Cloudflare.create_upload(lecture, cors_origin: "http://localhost:4000")
    end

    test "maps Cloudflare processing and ready states to the media behaviour" do
      Req.Test.stub(Cloudflare, fn conn ->
        assert conn.request_path == "/client/v4/accounts/test-account-id/stream/video-123"

        Req.Test.json(conn, %{
          success: true,
          result: %{uid: "video-123", readyToStream: false, status: %{state: "inprogress"}}
        })
      end)

      assert {:ok, :processing} = Cloudflare.upload_status("video-123")
    end
  end

  setup do
    private_key = :public_key.generate_key({:rsa, 1024, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private_key)])

    previous_key = Application.get_env(:wasomi, :cloudflare_stream_signing_private_key)
    previous_id = Application.get_env(:wasomi, :cloudflare_stream_signing_key_id)

    Application.put_env(:wasomi, :cloudflare_stream_signing_private_key, Base.encode64(pem))
    Application.put_env(:wasomi, :cloudflare_stream_signing_key_id, "test-key")

    on_exit(fn ->
      restore_env(:cloudflare_stream_signing_private_key, previous_key)
      restore_env(:cloudflare_stream_signing_key_id, previous_id)
    end)

    %{private_key: private_key}
  end

  test "Cloudflare signs playback JWTs with enough lifetime for the lecture", %{
    private_key: private_key
  } do
    lecture =
      lecture_fixture(
        video_provider: :cloudflare,
        video_asset_id: "signed-playback-id",
        duration_seconds: 900
      )

    user = user_fixture()
    other_user = user_fixture()
    issued_after = System.system_time(:second)

    assert {:ok, token} = Cloudflare.playback_token(lecture, user, 300)
    assert {:ok, other_token} = Cloudflare.playback_token(lecture, other_user, 300)
    assert token == other_token

    [header_segment, claims_segment, signature_segment] = String.split(token, ".")
    claims = claims_segment |> Base.url_decode64!(padding: false) |> Jason.decode!()
    header = header_segment |> Base.url_decode64!(padding: false) |> Jason.decode!()

    assert header == %{"alg" => "RS256", "kid" => "test-key"}
    assert claims["sub"] == "signed-playback-id"
    assert claims["kid"] == "test-key"
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
      lecture_fixture(
        video_provider: :cloudflare,
        video_asset_id: "av1Ab2_XyZ-9",
        duration_seconds: 120
      )

    user = user_fixture()

    assert {:ok, url} = Cloudflare.thumbnail_url(lecture, user)
    assert String.starts_with?(url, "https://customer-test-customer-code.cloudflarestream.com/")
    assert String.ends_with?(url, "/thumbnails/thumbnail.jpg")

    token = url |> String.split("/") |> Enum.at(-3)
    assert [_header, _claims, _signature] = String.split(token, ".")

    # playback_id is a path segment (URI.encode/1), token is a query value
    # (URI.encode_www_form/1) — assert each survives its actual encoder
    # unmangled for a real generated JWT, rather than assuming it.
    assert URI.encode_www_form(token) == token
    refute token =~ "%"
  end

  test "delivery URLs accept the full Cloudflare customer hostname" do
    previous_code = Application.get_env(:wasomi, :cloudflare_stream_customer_code)

    Application.put_env(
      :wasomi,
      :cloudflare_stream_customer_code,
      "customer-up8nrq4n6u7emwif.cloudflarestream.com"
    )

    on_exit(fn -> restore_env(:cloudflare_stream_customer_code, previous_code) end)

    assert Cloudflare.delivery_url("signed.jwt.token", "/manifest/video.m3u8") ==
             "https://customer-up8nrq4n6u7emwif.cloudflarestream.com/signed.jwt.token/manifest/video.m3u8"
  end

  test "download_url/1 rejects a non-Cloudflare lecture" do
    lecture = lecture_fixture(video_provider: :bunny, video_asset_id: "some-id")
    assert {:error, {:unsupported_video_provider, :bunny}} = Cloudflare.download_url(lecture)
  end

  defp restore_env(key, nil), do: Application.delete_env(:wasomi, key)
  defp restore_env(key, value), do: Application.put_env(:wasomi, key, value)

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end
end
