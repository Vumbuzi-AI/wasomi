defmodule WasomiWeb.MagicLinkSessionController do
  use WasomiWeb, :controller

  alias Wasomi.Accounts
  alias WasomiWeb.UserAuth

  # GET only peeks — mail-security scanners pre-fetch links and would burn a
  # one-time token on a mutating GET. The POST below actually consumes it.
  def show(conn, %{"token" => token}) do
    case Accounts.get_user_by_magic_token(token) do
      %Accounts.User{} = user ->
        conn
        |> assign(:token, token)
        |> assign(:pending_user, user)
        |> render(:show, layout: false)

      nil ->
        invalid(conn)
    end
  end

  def create(conn, %{"token" => token} = params) do
    case Accounts.login_user_by_magic_token(token) do
      {:ok, user} -> UserAuth.log_in_user(conn, user, params)
      :error -> invalid(conn)
    end
  end

  defp invalid(conn) do
    conn
    |> put_flash(:error, "That login link is invalid or has expired. Request a new one.")
    |> redirect(to: ~p"/users/log_in")
  end
end
