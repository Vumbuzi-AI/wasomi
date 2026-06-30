defmodule Wasomi.Media.Demo do
  @moduledoc """
  Development media adapter that streams ready-made public HLS samples.

  Lets the course player work end-to-end locally without Mux credentials.
  `Lecture.video_asset_id` is expected to hold a full HLS (`.m3u8`) URL, which
  `Wasomi.Media` streams directly without a signed token. Not for production.
  """

  @behaviour Wasomi.Media

  alias Wasomi.Accounts.User
  alias Wasomi.Catalog.Lecture

  @impl true
  def create_upload(_lecture, _opts), do: {:error, :demo_provider_does_not_support_uploads}

  @impl true
  def upload_status(_upload_id), do: {:error, :demo_provider_does_not_support_uploads}

  @impl true
  def playback_token(%Lecture{}, %User{}, _ttl), do: {:ok, ""}
end
