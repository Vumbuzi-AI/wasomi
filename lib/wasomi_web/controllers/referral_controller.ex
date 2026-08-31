defmodule WasomiWeb.ReferralController do
  use WasomiWeb, :controller

  # The `:referral_capture` plug on the :browser pipeline has already stored
  # `?ref=`; a signed-in user just goes to their dashboard, everyone else to
  # registration.
  def join(conn, _params) do
    case conn.assigns[:current_user] do
      %Wasomi.Accounts.User{} = user ->
        redirect(conn, to: WasomiWeb.UserAuth.signed_in_path(user))

      _ ->
        redirect(conn, to: ~p"/users/register")
    end
  end
end
