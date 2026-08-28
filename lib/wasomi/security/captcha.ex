defmodule Wasomi.Security.Captcha do
  @moduledoc """
  Verifies Google reCAPTCHA tokens against Google's `siteverify` API.

  v3 (`verify/2`) is the primary, frictionless check. It's score-based and
  probabilistic, not a verdict — Google's own guidance is to never gate a
  critical flow on it alone. `verify_v2/1` is the fallback: a real checkbox
  challenge, rendered client-side only when v3 comes back low-score or
  can't run at all (script blocked, etc.), with a plain success/failure
  result instead of a score to threshold.

  In test mode, or when the relevant site key isn't configured, both
  verifications succeed automatically, to allow local development and
  fast, isolated CI testing.
  """

  @verify_url "https://www.google.com/recaptcha/api/siteverify"
  @default_min_score 0.5

  @doc """
  Verifies a v3 `token` returned by Google reCAPTCHA.

  ## Options
    * `:action` - the expected action name (e.g. `"register"`, `"reset_password"`). Optional.
    * `:min_score` - the minimum score threshold (0.0 - 1.0). Defaults to 0.5.
    * `:remote_ip` - the user's remote IP address. Optional.

  ## Returns
    * `{:ok, %{score: float(), action: String.t() | nil}}` on successful verification.
    * `{:error, :low_score}` when the score is below the threshold — the caller should
      offer the `verify_v2/1` fallback rather than treating this as a hard failure.
    * `{:error, reason}` on any other failure.
  """
  def verify(token, opts \\ [])

  def verify(token, _opts) when not is_binary(token) or token == "" do
    if mock_enabled?() or not enabled?() do
      {:ok, %{score: 1.0, action: nil}}
    else
      {:error, :missing_token}
    end
  end

  def verify(token, opts) do
    if mock_enabled?() or not enabled?() do
      {:ok, %{score: 1.0, action: Keyword.get(opts, :action)}}
    else
      # enabled?/0 true means the site key is configured; a missing secret
      # key here is a misconfiguration, not "captcha off" — fails closed
      # instead of silently accepting any token.
      secret_key = Application.get_env(:wasomi, :recaptcha_secret_key)

      if is_nil(secret_key) or secret_key == "" do
        {:error, :missing_secret_key}
      else
        do_verify(token, secret_key, opts)
      end
    end
  end

  @doc """
  Verifies whichever token a form submitted, dispatching to `verify/2` or
  `verify_v2/1` based on the `"captcha_version"` field the JS hook sets
  alongside `"captcha_token"` — `"v2"` for a solved fallback checkbox,
  anything else (including absent, e.g. a stale cached page) as v3.
  """
  def verify_from_params(params, opts \\ [])

  def verify_from_params(%{"captcha_version" => "v2"} = params, _opts) do
    verify_v2(Map.get(params, "captcha_token"))
  end

  def verify_from_params(params, opts) do
    verify(Map.get(params, "captcha_token"), opts)
  end

  @doc """
  Verifies a v2 checkbox `token` — the fallback path a form renders when
  `verify/2` returns `{:error, :low_score}` or the client reports v3 never
  ran at all. Google's v2 response has no score to threshold: it's a plain
  pass/fail.
  """
  def verify_v2(token)

  def verify_v2(token) when not is_binary(token) or token == "" do
    if mock_enabled?() or not v2_enabled?() do
      {:ok, %{score: 1.0, action: nil}}
    else
      {:error, :missing_token}
    end
  end

  def verify_v2(token) do
    if mock_enabled?() or not v2_enabled?() do
      {:ok, %{score: 1.0, action: nil}}
    else
      secret_key = Application.get_env(:wasomi, :recaptcha_v2_secret_key)

      if is_nil(secret_key) or secret_key == "" do
        {:error, :missing_secret_key}
      else
        do_verify_v2(token, secret_key)
      end
    end
  end

  @doc """
  Returns the configured public v3 site key, or `nil` if unset.
  """
  def site_key do
    Application.get_env(:wasomi, :recaptcha_site_key)
  end

  @doc """
  Returns the configured public v2 site key, or `nil` if unset.
  """
  def v2_site_key do
    Application.get_env(:wasomi, :recaptcha_v2_site_key)
  end

  @doc """
  Returns true if the v3 site key is present and configured.
  """
  def enabled? do
    is_binary(site_key()) and site_key() != ""
  end

  @doc """
  Returns true if the v2 site key is present and configured — gates
  whether a form can actually offer the v2 fallback widget.
  """
  def v2_enabled? do
    is_binary(v2_site_key()) and v2_site_key() != ""
  end

  defp mock_enabled? do
    Application.get_env(:wasomi, :recaptcha_mock, false)
  end

  defp do_verify(token, secret_key, opts) do
    case post_verify(token, secret_key, Keyword.get(opts, :remote_ip)) do
      {:ok, body} ->
        score = Map.get(body, "score", 1.0)
        action = Map.get(body, "action")
        min_score = Keyword.get(opts, :min_score, @default_min_score)
        expected_action = Keyword.get(opts, :action)

        cond do
          score < min_score ->
            {:error, :low_score}

          expected_action && action && action != expected_action ->
            {:error, :action_mismatch}

          true ->
            {:ok, %{score: score, action: action}}
        end

      error ->
        error
    end
  end

  defp do_verify_v2(token, secret_key) do
    case post_verify(token, secret_key, nil) do
      {:ok, _body} -> {:ok, %{score: 1.0, action: nil}}
      error -> error
    end
  end

  # Shared HTTP call + response classification for both versions — v3 and
  # v2 only differ in how they interpret a *successful* body (a score to
  # threshold vs. a plain pass), not in how the request is made or how
  # failure responses are read.
  defp post_verify(token, secret_key, remote_ip) do
    params = [secret: secret_key, response: token] |> maybe_put_ip(remote_ip)
    req_options = Application.get_env(:wasomi, :recaptcha_req_options, [])

    request_opts =
      [
        form: params,
        receive_timeout: 10_000,
        retry: :transient,
        max_retries: 1
      ]
      |> Keyword.merge(req_options)

    case Req.post(@verify_url, request_opts) do
      {:ok, %{status: 200, body: %{"success" => true} = body}} ->
        {:ok, body}

      {:ok, %{status: 200, body: %{"success" => false, "error-codes" => error_codes}}} ->
        {:error, {:google_error, error_codes}}

      {:ok, %{status: 200, body: %{"success" => false}}} ->
        {:error, :verification_failed}

      {:ok, response} ->
        {:error, {:unexpected_response, response.status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put_ip(params, ip) when is_binary(ip) and ip != "", do: params ++ [remoteip: ip]
  defp maybe_put_ip(params, _), do: params
end
