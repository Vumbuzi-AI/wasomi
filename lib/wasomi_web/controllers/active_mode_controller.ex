defmodule WasomiWeb.ActiveModeController do
  use WasomiWeb, :controller

  alias Wasomi.Accounts

  @doc """
  Toggles the active operating mode in the session between `:admin` and `:learner`.

  Only base `:admin` accounts are authorized to change active modes.
  """
  def create(conn, %{"mode" => mode}) when mode in ["admin", "learner"] do
    user = conn.assigns.current_user

    if user && user.role == :admin do
      from_mode = get_session(conn, :active_mode) || "admin"
      to_mode = mode

      if from_mode != to_mode do
        audit_attrs = WasomiWeb.UserAuth.audit_request_attrs(conn)

        Accounts.record_account_audit_event(
          user,
          :active_mode_changed,
          audit_attrs ++ [metadata: %{from_mode: from_mode, to_mode: to_mode}]
        )
      end

      destination = if mode == "learner", do: ~p"/dashboard", else: ~p"/admin"

      flash_message =
        if mode == "learner", do: "Switched to Learner Mode.", else: "Switched to Admin Mode."

      conn
      |> put_session(:active_mode, mode)
      |> put_flash(:info, flash_message)
      |> redirect(to: destination)
    else
      conn
      |> put_flash(:error, "You are not authorized to switch operating modes.")
      |> redirect(to: ~p"/dashboard")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Invalid operating mode requested.")
    |> redirect(to: ~p"/dashboard")
  end
end
