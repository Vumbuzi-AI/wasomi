defmodule Wasomi.Security.CaptchaTest do
  use ExUnit.Case, async: false

  alias Wasomi.Security.Captcha

  setup do
    initial_mock = Application.get_env(:wasomi, :recaptcha_mock)
    initial_site_key = Application.get_env(:wasomi, :recaptcha_site_key)
    initial_secret_key = Application.get_env(:wasomi, :recaptcha_secret_key)
    initial_v2_site_key = Application.get_env(:wasomi, :recaptcha_v2_site_key)
    initial_v2_secret_key = Application.get_env(:wasomi, :recaptcha_v2_secret_key)
    initial_req_opts = Application.get_env(:wasomi, :recaptcha_req_options)

    on_exit(fn ->
      Application.put_env(:wasomi, :recaptcha_mock, initial_mock)
      Application.put_env(:wasomi, :recaptcha_site_key, initial_site_key)
      Application.put_env(:wasomi, :recaptcha_secret_key, initial_secret_key)
      Application.put_env(:wasomi, :recaptcha_v2_site_key, initial_v2_site_key)
      Application.put_env(:wasomi, :recaptcha_v2_secret_key, initial_v2_secret_key)
      Application.put_env(:wasomi, :recaptcha_req_options, initial_req_opts)
    end)

    :ok
  end

  describe "site_key/0 and enabled?/0" do
    test "returns site key and enabled status correctly" do
      Application.put_env(:wasomi, :recaptcha_site_key, nil)
      assert Captcha.site_key() == nil
      refute Captcha.enabled?()

      Application.put_env(:wasomi, :recaptcha_site_key, "")
      refute Captcha.enabled?()

      Application.put_env(:wasomi, :recaptcha_site_key, "test-site-key")
      assert Captcha.site_key() == "test-site-key"
      assert Captcha.enabled?()
    end
  end

  describe "verify/2 in mock / unconfigured mode" do
    test "succeeds when mock is enabled" do
      Application.put_env(:wasomi, :recaptcha_mock, true)

      assert {:ok, %{score: 1.0, action: "register"}} =
               Captcha.verify("token", action: "register")

      assert {:ok, %{score: 1.0}} = Captcha.verify("")
    end

    test "succeeds when neither key is set and not in mock mode" do
      Application.put_env(:wasomi, :recaptcha_mock, false)
      Application.put_env(:wasomi, :recaptcha_site_key, nil)
      Application.put_env(:wasomi, :recaptcha_secret_key, nil)

      assert {:ok, %{score: 1.0, action: "register"}} =
               Captcha.verify("token", action: "register")
    end

    test "fails closed when the site key is set but the secret key is missing" do
      Application.put_env(:wasomi, :recaptcha_mock, false)
      Application.put_env(:wasomi, :recaptcha_site_key, "test-site-key")
      Application.put_env(:wasomi, :recaptcha_secret_key, nil)

      assert {:error, :missing_secret_key} = Captcha.verify("any-token", action: "register")
    end
  end

  describe "verify/2 with Google API verification via Req.Test plug" do
    setup do
      Application.put_env(:wasomi, :recaptcha_mock, false)
      Application.put_env(:wasomi, :recaptcha_site_key, "valid-site-key")
      Application.put_env(:wasomi, :recaptcha_secret_key, "valid-secret-key")
      :ok
    end

    test "returns :missing_token when token is blank, nil, or invalid type and recaptcha is enabled" do
      assert {:error, :missing_token} = Captcha.verify("")
      assert {:error, :missing_token} = Captcha.verify(nil)
      assert {:error, :missing_token} = Captcha.verify(123)
      assert {:error, :missing_token} = Captcha.verify(%{})
    end

    test "succeeds when Google returns success with a high score and matching action" do
      Req.Test.stub(Wasomi.Security.Captcha, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        assert params["secret"] == "valid-secret-key"
        assert params["response"] == "good-token"

        Req.Test.json(conn, %{
          "success" => true,
          "score" => 0.9,
          "action" => "register",
          "challenge_ts" => "2026-08-27T12:00:00Z",
          "hostname" => "localhost"
        })
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      assert {:ok, %{score: 0.9, action: "register"}} =
               Captcha.verify("good-token", action: "register")
    end

    test "forwards remote_ip parameter when provided" do
      Req.Test.stub(Wasomi.Security.Captcha, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        assert params["remoteip"] == "192.168.1.100"

        Req.Test.json(conn, %{
          "success" => true,
          "score" => 0.95,
          "action" => "register"
        })
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      assert {:ok, %{score: 0.95, action: "register"}} =
               Captcha.verify("token-with-ip", action: "register", remote_ip: "192.168.1.100")
    end

    test "respects a custom min_score threshold" do
      Req.Test.stub(Wasomi.Security.Captcha, fn conn ->
        Req.Test.json(conn, %{
          "success" => true,
          "score" => 0.6,
          "action" => "register"
        })
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      # 0.6 is >= default 0.5 -> succeeds
      assert {:ok, %{score: 0.6, action: "register"}} =
               Captcha.verify("token", action: "register")

      # 0.6 is < custom 0.8 -> fails with :low_score
      assert {:error, :low_score} =
               Captcha.verify("token", action: "register", min_score: 0.8)
    end

    test "returns :low_score when score is below the threshold" do
      Req.Test.stub(Wasomi.Security.Captcha, fn conn ->
        Req.Test.json(conn, %{
          "success" => true,
          "score" => 0.2,
          "action" => "register"
        })
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      assert {:error, :low_score} = Captcha.verify("bot-token", action: "register")
    end

    test "returns :action_mismatch when returned action differs from expected" do
      Req.Test.stub(Wasomi.Security.Captcha, fn conn ->
        Req.Test.json(conn, %{
          "success" => true,
          "score" => 0.9,
          "action" => "other_action"
        })
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      assert {:error, :action_mismatch} = Captcha.verify("token", action: "register")
    end

    test "returns {:google_error, codes} when Google returns success: false" do
      Req.Test.stub(Wasomi.Security.Captcha, fn conn ->
        Req.Test.json(conn, %{
          "success" => false,
          "error-codes" => ["invalid-input-response"]
        })
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      assert {:error, {:google_error, ["invalid-input-response"]}} = Captcha.verify("bad-token")
    end

    test "returns {:unexpected_response, status} when Google returns a non-200 HTTP response" do
      Req.Test.stub(Wasomi.Security.Captcha, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      assert {:error, {:unexpected_response, 500}} = Captcha.verify("token")
    end
  end

  describe "verify_v2/1" do
    test "succeeds when mock is enabled" do
      Application.put_env(:wasomi, :recaptcha_mock, true)
      assert {:ok, %{score: 1.0}} = Captcha.verify_v2("token")
    end

    test "succeeds when v2 isn't configured, so a form without a v2 fallback never blocks" do
      Application.put_env(:wasomi, :recaptcha_mock, false)
      Application.put_env(:wasomi, :recaptcha_v2_site_key, nil)
      assert {:ok, %{score: 1.0}} = Captcha.verify_v2("token")
    end

    test "returns :missing_token for a blank or absent token when v2 is enabled" do
      Application.put_env(:wasomi, :recaptcha_mock, false)
      Application.put_env(:wasomi, :recaptcha_v2_site_key, "v2-site-key")
      Application.put_env(:wasomi, :recaptcha_v2_secret_key, "v2-secret-key")

      assert {:error, :missing_token} = Captcha.verify_v2("")
      assert {:error, :missing_token} = Captcha.verify_v2(nil)
    end

    test "fails closed when the v2 site key is set but the v2 secret key is missing" do
      Application.put_env(:wasomi, :recaptcha_mock, false)
      Application.put_env(:wasomi, :recaptcha_v2_site_key, "v2-site-key")
      Application.put_env(:wasomi, :recaptcha_v2_secret_key, nil)

      assert {:error, :missing_secret_key} = Captcha.verify_v2("any-token")
    end

    test "accepts any successful response regardless of score — v2 has no threshold" do
      Application.put_env(:wasomi, :recaptcha_mock, false)
      Application.put_env(:wasomi, :recaptcha_v2_site_key, "v2-site-key")
      Application.put_env(:wasomi, :recaptcha_v2_secret_key, "v2-secret-key")

      Req.Test.stub(Wasomi.Security.Captcha, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        assert params["secret"] == "v2-secret-key"
        assert params["response"] == "checkbox-token"

        Req.Test.json(conn, %{"success" => true, "challenge_ts" => "2026-08-27T12:00:00Z"})
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      assert {:ok, %{score: 1.0}} = Captcha.verify_v2("checkbox-token")
    end

    test "returns {:google_error, codes} for an unsuccessful v2 response" do
      Application.put_env(:wasomi, :recaptcha_mock, false)
      Application.put_env(:wasomi, :recaptcha_v2_site_key, "v2-site-key")
      Application.put_env(:wasomi, :recaptcha_v2_secret_key, "v2-secret-key")

      Req.Test.stub(Wasomi.Security.Captcha, fn conn ->
        Req.Test.json(conn, %{"success" => false, "error-codes" => ["invalid-input-response"]})
      end)

      Application.put_env(:wasomi, :recaptcha_req_options,
        plug: {Req.Test, Wasomi.Security.Captcha},
        retry: false
      )

      assert {:error, {:google_error, ["invalid-input-response"]}} =
               Captcha.verify_v2("bad-token")
    end
  end

  describe "verify_from_params/2" do
    test "dispatches to verify_v2/1 when captcha_version is \"v2\"" do
      Application.put_env(:wasomi, :recaptcha_mock, true)

      assert {:ok, %{score: 1.0}} =
               Captcha.verify_from_params(%{
                 "captcha_version" => "v2",
                 "captcha_token" => "token"
               })
    end

    test "dispatches to verify/2 (v3) when captcha_version is absent or anything else" do
      Application.put_env(:wasomi, :recaptcha_mock, true)

      assert {:ok, %{action: "register"}} =
               Captcha.verify_from_params(%{"captcha_token" => "token"}, action: "register")

      assert {:ok, %{action: "register"}} =
               Captcha.verify_from_params(
                 %{"captcha_version" => "v3", "captcha_token" => "token"},
                 action: "register"
               )
    end
  end
end
