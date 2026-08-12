defmodule WasomiWeb.ResourceController do
  use WasomiWeb, :controller

  alias Wasomi.Accounts.User
  alias Wasomi.{Catalog, Enrollments, Storage}
  alias Wasomi.Catalog.LectureResource

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
        case resolve_download_url(resource) do
          {:ok, url} -> redirect(conn, external: url)
          {:error, _reason} -> send_resp(conn, :not_found, "This resource is unavailable.")
        end

      {:error, :forbidden} ->
        send_resp(conn, :forbidden, "Active enrollment required.")
    end
  end

  # A `:link` resource's URL is validated (http/https, real host) at
  # changeset time, but re-checked here too — a redirect target should
  # never be trusted purely because it once passed validation on write.
  defp resolve_download_url(%LectureResource{kind: :link, url: url}) do
    if LectureResource.valid_url?(url), do: {:ok, url}, else: {:error, :invalid_url}
  end

  # `:document`/`:video` resources are recomputed from storage_key rather
  # than trusting the stored `url` column, which can be nil if R2_PUBLIC_URL
  # wasn't configured at upload time.
  defp resolve_download_url(%LectureResource{storage_key: key})
       when is_binary(key) and key != "" do
    Storage.download_url(key)
  end

  defp resolve_download_url(_resource), do: {:error, :missing_storage_reference}
end
