defmodule WasomiWeb.UserAuthTest do
  use WasomiWeb.ConnCase, async: true

  alias Phoenix.LiveView
  alias Wasomi.Accounts
  alias Wasomi.Accounts.AuditEvent
  alias WasomiWeb.UserAuth
  import Wasomi.AccountsFixtures

  @remember_me_cookie "_wasomi_web_user_remember_me"

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, WasomiWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{user: user_fixture(), conn: conn}
  end

  describe "log_in_user/3" do
    test "stores the user token in the session", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("user-agent", "WasomiTest/1.0")
        |> UserAuth.log_in_user(user)

      assert token = get_session(conn, :user_token)
      assert get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(token)}"
      assert redirected_to(conn) == ~p"/dashboard"
      assert Accounts.get_user_by_session_token(token)

      assert %AuditEvent{
               event: :login_succeeded,
               user_id: user_id,
               ip_address: "127.0.0.1",
               user_agent: "WasomiTest/1.0"
             } = Accounts.list_account_audit_events(user) |> List.first()

      assert user_id == user.id
    end

    test "records the sign-in on the user record", %{conn: conn, user: user} do
      assert is_nil(user.last_signed_in_at)

      UserAuth.log_in_user(conn, user)

      assert %DateTime{} = Accounts.get_user!(user.id).last_signed_in_at
    end

    test "redirects administrators to the admin area", %{conn: conn, user: user} do
      {:ok, admin} = Accounts.update_user_role(user, :admin)

      conn = UserAuth.log_in_user(conn, admin)

      assert redirected_to(conn) == ~p"/admin"
    end

    test "redirects unconfirmed users to the confirmation instructions page", %{conn: conn} do
      user = user_fixture(confirmed: false)

      conn = UserAuth.log_in_user(conn, user)

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/confirm"
    end

    test "clears everything previously stored in the session", %{conn: conn, user: user} do
      conn = conn |> put_session(:to_be_removed, "value") |> UserAuth.log_in_user(user)
      refute get_session(conn, :to_be_removed)
    end

    test "redirects to the configured path", %{conn: conn, user: user} do
      conn = conn |> put_session(:user_return_to, "/hello") |> UserAuth.log_in_user(user)
      assert redirected_to(conn) == "/hello"
    end

    test "writes a cookie if remember_me is configured", %{conn: conn, user: user} do
      conn = conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})
      assert get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :user_token)
      assert max_age == 5_184_000
    end
  end

  describe "logout_user/1" do
    test "erases session and cookies", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> put_req_cookie(@remember_me_cookie, user_token)
        |> fetch_cookies()
        |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
      refute Accounts.get_user_by_session_token(user_token)

      assert %AuditEvent{event: :logout, user_id: user_id} =
               Accounts.list_account_audit_events(user) |> List.first()

      assert user_id == user.id
    end

    test "broadcasts to the given live_socket_id", %{conn: conn} do
      live_socket_id = "users_sessions:abcdef-token"
      WasomiWeb.Endpoint.subscribe(live_socket_id)

      conn
      |> put_session(:live_socket_id, live_socket_id)
      |> UserAuth.log_out_user()

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^live_socket_id}
    end

    test "works even if user is already logged out", %{conn: conn} do
      conn = conn |> fetch_cookies() |> UserAuth.log_out_user()
      refute get_session(conn, :user_token)
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "fetch_current_user/2" do
    test "authenticates user from session", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      conn = conn |> put_session(:user_token, user_token) |> UserAuth.fetch_current_user([])
      assert conn.assigns.current_user.id == user.id
    end

    test "authenticates user from cookies", %{conn: conn, user: user} do
      logged_in_conn =
        conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      user_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user.id == user.id
      assert get_session(conn, :user_token) == user_token

      assert get_session(conn, :live_socket_id) ==
               "users_sessions:#{Base.url_encode64(user_token)}"
    end

    test "does not authenticate if data is missing", %{conn: conn, user: user} do
      _ = Accounts.generate_user_session_token(user)
      conn = UserAuth.fetch_current_user(conn, [])
      refute get_session(conn, :user_token)
      refute conn.assigns.current_user
    end
  end

  describe "on_mount :mount_current_user" do
    test "assigns current_user based on a valid user_token", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user.id == user.id
    end

    test "assigns nil to current_user assign if there isn't a valid user_token", %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user == nil
    end

    test "assigns nil to current_user assign if there isn't a user_token", %{conn: conn} do
      session = conn |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user == nil
    end
  end

  describe "on_mount :ensure_authenticated" do
    test "authenticates current_user based on a valid user_token", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:ensure_authenticated, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user.id == user.id
    end

    test "redirects unconfirmed users to confirmation instructions", %{conn: conn} do
      user = user_fixture(confirmed: false)
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = live_socket()

      assert {:halt, updated_socket} =
               UserAuth.on_mount(:ensure_authenticated, %{}, session, socket)

      assert updated_socket.assigns.current_user.id == user.id

      assert {:redirect, %{to: "/users/confirm"}} = updated_socket.redirected

      assert Phoenix.Flash.get(updated_socket.assigns.flash, :error) ==
               "Please confirm your email before continuing."
    end

    test "redirects to login page if there isn't a valid user_token", %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = live_socket()

      {:halt, updated_socket} = UserAuth.on_mount(:ensure_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_user == nil
    end

    test "redirects to login page if there isn't a user_token", %{conn: conn} do
      session = conn |> get_session()

      socket = live_socket()

      {:halt, updated_socket} = UserAuth.on_mount(:ensure_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_user == nil
    end
  end

  describe "on_mount :redirect_admins_from_learner_area" do
    test "silently sends admins in admin mode to /admin", %{conn: conn, user: user} do
      {:ok, admin} = Accounts.update_user_role(user, :admin)
      user_token = Accounts.generate_user_session_token(admin)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      assert {:halt, updated_socket} =
               UserAuth.on_mount(
                 :redirect_admins_from_learner_area,
                 %{},
                 session,
                 live_socket()
               )

      assert {:redirect, %{to: "/admin"}} = updated_socket.redirected
      assert updated_socket.assigns.flash == %{}
    end

    test "lets admins in learner mode through", %{conn: conn, user: user} do
      {:ok, admin} = Accounts.update_user_role(user, :admin)
      user_token = Accounts.generate_user_session_token(admin)

      session =
        conn
        |> put_session(:user_token, user_token)
        |> put_session(:active_mode, "learner")
        |> get_session()

      assert {:cont, updated_socket} =
               UserAuth.on_mount(
                 :redirect_admins_from_learner_area,
                 %{},
                 session,
                 %LiveView.Socket{}
               )

      assert updated_socket.assigns.current_user.id == admin.id
      assert updated_socket.assigns.active_mode == :learner
    end

    test "lets learners through", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      assert {:cont, updated_socket} =
               UserAuth.on_mount(
                 :redirect_admins_from_learner_area,
                 %{},
                 session,
                 %LiveView.Socket{}
               )

      assert updated_socket.assigns.current_user.id == user.id
      assert updated_socket.assigns.active_mode == :learner
    end
  end

  describe "on_mount :redirect_if_user_is_authenticated" do
    test "redirects if there is an authenticated  user ", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      assert {:halt, _updated_socket} =
               UserAuth.on_mount(
                 :redirect_if_user_is_authenticated,
                 %{},
                 session,
                 %LiveView.Socket{}
               )
    end

    test "doesn't redirect if there is no authenticated user", %{conn: conn} do
      session = conn |> get_session()

      assert {:cont, _updated_socket} =
               UserAuth.on_mount(
                 :redirect_if_user_is_authenticated,
                 %{},
                 session,
                 %LiveView.Socket{}
               )
    end
  end

  describe "redirect_if_user_is_authenticated/2" do
    test "redirects if user is authenticated", %{conn: conn, user: user} do
      conn = conn |> assign(:current_user, user) |> UserAuth.redirect_if_user_is_authenticated([])
      assert conn.halted
      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "does not redirect if user is not authenticated", %{conn: conn} do
      conn = UserAuth.redirect_if_user_is_authenticated(conn, [])
      refute conn.halted
      refute conn.status
    end
  end

  describe "require_authenticated_user/2" do
    test "redirects if user is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> UserAuth.require_authenticated_user([])
      assert conn.halted

      assert redirected_to(conn) == ~p"/users/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must log in to access this page."
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      refute get_session(halted_conn, :user_return_to)
    end

    test "does not redirect if user is authenticated", %{conn: conn, user: user} do
      conn = conn |> assign(:current_user, user) |> UserAuth.require_authenticated_user([])
      refute conn.halted
      refute conn.status
    end

    test "redirects unconfirmed users to confirmation instructions", %{conn: conn} do
      user = user_fixture(confirmed: false)

      conn =
        conn
        |> fetch_flash()
        |> assign(:current_user, user)
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/users/confirm"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Please confirm your email before continuing."

      refute get_session(conn, :user_return_to)
    end
  end

  describe "administrator authorization" do
    test "require_admin/2 allows administrators", %{conn: conn, user: user} do
      {:ok, admin} = Accounts.update_user_role(user, :admin)

      conn = conn |> assign(:current_user, admin) |> UserAuth.require_admin([])

      refute conn.halted
      refute conn.status
    end

    test "require_admin/2 rejects unconfirmed administrators before role authorization", %{
      conn: conn
    } do
      user = user_fixture(confirmed: false)
      {:ok, admin} = Accounts.update_user_role(user, :admin)

      conn =
        conn
        |> fetch_flash()
        |> assign(:current_user, admin)
        |> UserAuth.require_admin([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/users/confirm"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Please confirm your email before continuing."
    end

    test "require_admin/2 quietly returns learners to their own area", %{conn: conn, user: user} do
      conn =
        conn
        |> fetch_flash()
        |> assign(:current_user, user)
        |> UserAuth.require_admin([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == nil
    end

    test "on_mount :ensure_admin allows administrators", %{conn: conn, user: user} do
      {:ok, admin} = Accounts.update_user_role(user, :admin)
      user_token = Accounts.generate_user_session_token(admin)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      assert {:cont, socket} =
               UserAuth.on_mount(:ensure_admin, %{}, session, %LiveView.Socket{})

      assert socket.assigns.current_user.role == :admin
    end

    test "on_mount :ensure_admin quietly returns learners to their own area", %{
      conn: conn,
      user: user
    } do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      assert {:halt, socket} =
               UserAuth.on_mount(:ensure_admin, %{}, session, live_socket())

      assert {:redirect, %{to: "/dashboard"}} = socket.redirected
      assert Phoenix.Flash.get(socket.assigns.flash, :error) == nil
    end

    test "require_admin/2 blocks administrators in learner mode and redirects with notice", %{
      conn: conn,
      user: user
    } do
      {:ok, admin} = Accounts.update_user_role(user, :admin)

      conn =
        conn
        |> fetch_flash()
        |> assign(:current_user, admin)
        |> assign(:active_mode, :learner)
        |> UserAuth.require_admin([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/dashboard"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Administrative actions are unavailable while in Learner Mode"
    end

    test "on_mount :ensure_admin blocks administrators in learner mode and redirects with notice",
         %{
           conn: conn,
           user: user
         } do
      {:ok, admin} = Accounts.update_user_role(user, :admin)
      user_token = Accounts.generate_user_session_token(admin)

      session =
        conn
        |> put_session(:user_token, user_token)
        |> put_session(:active_mode, "learner")
        |> get_session()

      assert {:halt, socket} =
               UserAuth.on_mount(:ensure_admin, %{}, session, live_socket())

      assert {:redirect, %{to: "/dashboard"}} = socket.redirected

      assert Phoenix.Flash.get(socket.assigns.flash, :error) =~
               "Administrative actions are unavailable while in Learner Mode"
    end

    test "on_mount :ensure_admin redirects unconfirmed administrators to confirmation", %{
      conn: conn
    } do
      user = user_fixture(confirmed: false)
      {:ok, admin} = Accounts.update_user_role(user, :admin)
      user_token = Accounts.generate_user_session_token(admin)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      assert {:halt, updated_socket} =
               UserAuth.on_mount(:ensure_admin, %{}, session, live_socket())

      assert {:redirect, %{to: "/users/confirm"}} = updated_socket.redirected

      assert Phoenix.Flash.get(updated_socket.assigns.flash, :error) ==
               "Please confirm your email before continuing."
    end
  end

  describe "active mode derivation and helpers" do
    test "derive_active_mode/2 resolves correctly and safely", %{user: user} do
      {:ok, admin} = Accounts.update_user_role(user, :admin)
      learner = user_fixture()

      assert UserAuth.derive_active_mode(admin, "learner") == :learner
      assert UserAuth.derive_active_mode(admin, "admin") == :admin
      assert UserAuth.derive_active_mode(admin, nil) == :admin
      assert UserAuth.derive_active_mode(admin, "other") == :admin

      assert UserAuth.derive_active_mode(learner, "admin") == :learner
      assert UserAuth.derive_active_mode(learner, "learner") == :learner
      assert UserAuth.derive_active_mode(learner, nil) == :learner

      assert UserAuth.derive_active_mode(nil, "admin") == :anonymous
      assert UserAuth.derive_active_mode(nil, nil) == :anonymous
    end

    test "admin_mode?/1 and learner_mode?/1 reflect assigns on conn and socket" do
      conn_admin = %Plug.Conn{assigns: %{active_mode: :admin}}
      conn_learner = %Plug.Conn{assigns: %{active_mode: :learner}}
      socket_admin = %LiveView.Socket{assigns: %{active_mode: :admin}}
      socket_learner = %LiveView.Socket{assigns: %{active_mode: :learner}}

      assert UserAuth.admin_mode?(conn_admin)
      refute UserAuth.learner_mode?(conn_admin)

      assert UserAuth.learner_mode?(conn_learner)
      refute UserAuth.admin_mode?(conn_learner)

      assert UserAuth.admin_mode?(socket_admin)
      refute UserAuth.learner_mode?(socket_admin)

      assert UserAuth.learner_mode?(socket_learner)
      refute UserAuth.admin_mode?(socket_learner)
    end
  end

  defp live_socket do
    %LiveView.Socket{
      endpoint: WasomiWeb.Endpoint,
      assigns: %{__changed__: %{}, flash: %{}}
    }
  end
end
