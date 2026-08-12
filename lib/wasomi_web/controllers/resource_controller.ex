defmodule WasomiWeb.ResourceController do
  use WasomiWeb, :controller

  alias Wasomi.Accounts.User
  alias Wasomi.{Catalog, Enrollments}

  def download(conn, %{"id" => id} = params) do
    resource = Catalog.get_lecture_resource!(id)
    user = conn.assigns.current_user

    # `preview` is a client-supplied param, so it's only ever honored once
    # `user` — read from the authenticated session, never from the request —
    # is confirmed to really be an admin, matching WasomiWeb.MediaController.
    authorization =
      if params["preview"] == "true" and match?(%User{role: :admin}, user) do
        {:ok, resource.lecture}
      else
        Enrollments.authorize_lecture(user, resource.lecture)
      end

    case authorization do
      {:ok, _lecture} ->
        redirect(conn, external: resource.url)

      {:error, :forbidden} ->
        send_resp(conn, :forbidden, "Active enrollment required.")
    end
  end
end
