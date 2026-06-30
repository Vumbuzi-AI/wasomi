defmodule Wasomi.MediaTest do
  use Wasomi.DataCase

  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures

  alias Wasomi.Media.Mux

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

  defp restore_env(key, nil), do: Application.delete_env(:wasomi, key)
  defp restore_env(key, value), do: Application.put_env(:wasomi, key, value)
end
