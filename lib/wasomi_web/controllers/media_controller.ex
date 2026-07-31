defmodule WasomiWeb.MediaController do
  use WasomiWeb, :controller

  require Logger

  alias Wasomi.Accounts.User
  alias Wasomi.{Catalog, Media}

  def playback(conn, %{"id" => id} = params) do
    lecture = Catalog.get_lecture!(id)
    user = conn.assigns.current_user

    # `preview` is a client-supplied param, so it's only ever honored once
    # `user` — read from the authenticated session, never from the
    # request — is confirmed to really be an admin. A non-admin appending
    # `?preview=true` themselves gains nothing; they fall straight through
    # to the normal pay-gated `playback_url/2` below.
    result =
      if params["preview"] == "true" and match?(%User{role: :admin}, user) do
        Media.playback_url_for_preview(user, lecture)
      else
        Media.playback_url(user, lecture)
      end

    case result do
      {:ok, playback} ->
        json(conn, playback)

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "active enrollment required"})

      {:error, reason} ->
        Logger.warning("protected playback unavailable: #{inspect(reason)}")

        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "video unavailable"})
    end
  end
end
