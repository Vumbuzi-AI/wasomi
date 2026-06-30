defmodule WasomiWeb.MediaController do
  use WasomiWeb, :controller

  require Logger

  alias Wasomi.{Catalog, Media}

  def playback(conn, %{"id" => id}) do
    lecture = Catalog.get_lecture!(id)

    case Media.playback_url(conn.assigns.current_user, lecture) do
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
