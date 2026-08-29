defmodule WasomiWeb.UserAuth do
  use WasomiWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Wasomi.Accounts

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_wasomi_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)
    :ok = record_account_audit_event(conn, user, :login_succeeded)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(user))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn, opts \\ []) do
    user_token = get_session(conn, :user_token)
    # A logout with an already-expired/invalid token can't be attributed to a
    # user, so no `:logout` event is recorded for it — accepted asymmetry with
    # login, where the session is by definition still valid.
    user = user_token && Accounts.get_user_by_session_token(user_token)
    user && record_account_audit_event(conn, user, :logout)
    user_token && Accounts.delete_user_session_token(user_token)
    redirect_to = Keyword.get(opts, :to, ~p"/")

    if live_socket_id = get_session(conn, :live_socket_id) do
      WasomiWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: redirect_to)
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Handles mounting and authenticating the current_user in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_user` - Assigns current_user
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:ensure_authenticated` - Authenticates the user from the session,
      and assigns the current_user to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

    * `:redirect_if_user_is_authenticated` - Authenticates the user from the session.
      Redirects to signed_in_path if there's a logged user.

    * `:ensure_admin` - Authenticates the user and only continues for the
      `admin` role.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the current_user:

      defmodule WasomiWeb.PageLive do
        use WasomiWeb, :live_view

        on_mount {WasomiWeb.UserAuth, :mount_current_user}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{WasomiWeb.UserAuth, :ensure_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    case socket.assigns.current_user do
      nil ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
          |> Phoenix.LiveView.redirect(to: ~p"/users/log_in")

        {:halt, socket}

      %{confirmed_at: nil} ->
        {:halt, redirect_unconfirmed_live_user(socket)}

      _user ->
        {:cont, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket.assigns.current_user))}
    else
      {:cont, socket}
    end
  end

  def on_mount(:ensure_admin, _params, session, socket) do
    socket = mount_current_user(socket, session)

    case socket.assigns.current_user do
      %{confirmed_at: nil} ->
        {:halt, redirect_unconfirmed_live_user(socket)}

      %{role: :admin} ->
        {:cont, Phoenix.Component.assign(socket, :page_title_suffix, " · Wasomi Admin")}

      nil ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
          |> Phoenix.LiveView.redirect(to: ~p"/users/log_in")

        {:halt, socket}

      _user ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "You do not have permission to access this page.")
          |> Phoenix.LiveView.redirect(to: ~p"/")

        {:halt, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end
    end)
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn.assigns.current_user))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "You must log in to access this page.")
        |> maybe_store_return_to()
        |> redirect(to: ~p"/users/log_in")
        |> halt()

      %{confirmed_at: nil} ->
        redirect_unconfirmed_conn(conn)

      _user ->
        conn
    end
  end

  @doc """
  Restricts controller routes to authenticated administrators.
  """
  def require_admin(conn, _opts) do
    case conn.assigns[:current_user] do
      # unreachable via router (require_authenticated_user already catches this) — kept for standalone calls
      %{confirmed_at: nil} ->
        redirect_unconfirmed_conn(conn)

      %{role: :admin} ->
        conn

      nil ->
        conn
        |> put_flash(:error, "You must log in to access this page.")
        |> maybe_store_return_to()
        |> redirect(to: ~p"/users/log_in")
        |> halt()

      _user ->
        conn
        |> put_flash(:error, "You do not have permission to access this page.")
        |> redirect(to: ~p"/")
        |> halt()
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  @doc """
  Where a user lands after auth actions that don't have their own explicit
  destination — unconfirmed users go back to the confirmation page, admins
  to `/admin`, everyone else to `/dashboard`.
  """
  def signed_in_path(%{confirmed_at: nil}), do: ~p"/users/confirm"
  def signed_in_path(%{role: :admin}), do: ~p"/admin"
  def signed_in_path(_user), do: ~p"/dashboard"

  defp redirect_unconfirmed_conn(conn) do
    conn
    |> put_flash(:error, "Please confirm your email before continuing.")
    |> redirect(to: ~p"/users/confirm")
    |> halt()
  end

  defp redirect_unconfirmed_live_user(socket) do
    socket
    |> Phoenix.LiveView.put_flash(:error, "Please confirm your email before continuing.")
    |> Phoenix.LiveView.redirect(to: ~p"/users/confirm")
  end

  defp record_account_audit_event(conn, user, event) do
    _result = Accounts.record_account_audit_event(user, event, audit_request_attrs(conn))
    :ok
  end

  @doc """
  Request provenance (`:ip_address`, `:user_agent`, `:request_id`) for an
  `Accounts.record_account_audit_event/3` call from a controller/plug.
  """
  def audit_request_attrs(conn) do
    [
      ip_address: remote_ip(conn),
      user_agent: conn |> get_req_header("user-agent") |> List.first(),
      request_id: conn |> get_resp_header("x-request-id") |> List.first()
    ]
  end

  # NOTE: reads `conn.remote_ip` directly. Behind a proxy/CDN/load balancer
  # this is the proxy address, not the client's — wire up `plug RemoteIp`
  # (with a trusted-proxy allowlist for the real deploy topology) in the
  # endpoint if a true client IP is needed in the audit trail.
  defp remote_ip(%{remote_ip: remote_ip}) when is_tuple(remote_ip) do
    remote_ip |> :inet.ntoa() |> to_string()
  end

  defp remote_ip(_conn), do: nil
end
