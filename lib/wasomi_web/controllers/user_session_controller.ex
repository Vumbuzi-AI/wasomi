defmodule WasomiWeb.UserSessionController do
  use WasomiWeb, :controller

  alias Wasomi.Accounts
  alias Wasomi.Security.Captcha
  alias WasomiWeb.UserAuth

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create_session(params, "Password updated successfully!")
  end

  def create(conn, params) do
    case Captcha.verify_from_params(params, action: "login") do
      {:ok, _} ->
        create_session(conn, params, "Welcome back!")

      # v3's score was too low to trust outright, but not necessarily a
      # bot — send the learner back with the v2 checkbox offered instead
      # of a dead end. This is a redirect (login POSTs to a plain
      # controller, not a LiveView event), so the signal to show it has to
      # travel as a query param rather than a socket assign.
      {:error, :low_score} ->
        # No flash here: mount/3 derives the same inline message itself from
        # the show_recaptcha_v2 param, so a flash would just duplicate it —
        # and unlike a real error, this isn't a toast-and-forget moment, it's
        # a persistent instruction that should stay put until the checkbox
        # is solved.
        email = get_in(params, ["user", "email"])
        record_failed_login(conn, nil, email, "captcha_low_score")

        conn
        |> put_flash(:email, if(email, do: String.slice(email, 0, 160), else: nil))
        |> redirect(to: ~p"/users/log_in?show_recaptcha_v2=true")

      {:error, _reason} ->
        email = get_in(params, ["user", "email"])
        record_failed_login(conn, nil, email, "captcha_failed")

        conn
        |> put_flash(:error, "Security verification failed. Please try again.")
        |> put_flash(:email, if(email, do: String.slice(email, 0, 160), else: nil))
        |> redirect(to: ~p"/users/log_in")
    end
  end

  defp create_session(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    case Accounts.get_user_by_email_and_password(email, password) do
      %Accounts.User{confirmed_at: nil} = user ->
        record_failed_login(conn, user, email, "unconfirmed")

        conn
        |> put_flash(
          :error,
          "Please confirm your email address before logging in. Check your inbox for the confirmation link."
        )
        |> redirect(to: ~p"/users/confirm?#{[email: email]}")

      %Accounts.User{} = user ->
        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      nil ->
        record_failed_login(conn, nil, email, "invalid_credentials")

        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log_in")
    end
  end

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end

  defp record_failed_login(conn, user, email, reason) do
    attrs =
      Keyword.put(
        UserAuth.audit_request_attrs(conn),
        :metadata,
        Map.put(Accounts.audit_email_metadata(email), "reason", reason)
      )

    _result = Accounts.record_account_audit_event(user, :login_failed, attrs)
    :ok
  end
end
