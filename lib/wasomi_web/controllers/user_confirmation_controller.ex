defmodule WasomiWeb.UserConfirmationController do
  use WasomiWeb, :controller

  alias Wasomi.Accounts
  alias WasomiWeb.UserAuth

  # GET only peeks at the token, never confirms — email scanners pre-fetch
  # links and would burn a one-time token on a mutating GET.
  def show(conn, %{"token" => token}) do
    case Accounts.get_user_by_confirmation_token(token) do
      %Accounts.User{confirmed_at: nil} = user ->
        conn
        |> assign(:token, token)
        |> assign(:pending_user, user)
        |> render(:show, layout: false)

      _not_found_or_already_confirmed ->
        handle_invalid_confirmation_link(conn)
    end
  end

  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user(token, UserAuth.audit_request_attrs(conn)) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user)

      :error ->
        handle_invalid_confirmation_link(conn)
    end
  end

  defp handle_invalid_confirmation_link(
         %{assigns: %{current_user: %{confirmed_at: confirmed_at}}} = conn
       )
       when not is_nil(confirmed_at) do
    redirect(conn, to: UserAuth.signed_in_path(conn.assigns.current_user))
  end

  defp handle_invalid_confirmation_link(conn) do
    conn
    |> put_flash(:error, "Confirmation link is invalid or it has expired.")
    |> redirect(to: ~p"/users/confirm")
  end
end
