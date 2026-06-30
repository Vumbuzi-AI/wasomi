defmodule Wasomi.Media.Unconfigured do
  @behaviour Wasomi.Media

  @impl true
  def create_upload(_lecture, _opts), do: {:error, :media_provider_not_configured}

  @impl true
  def upload_status(_upload_id), do: {:error, :media_provider_not_configured}

  @impl true
  def playback_token(_lecture, _user, _ttl), do: {:error, :media_provider_not_configured}
end
