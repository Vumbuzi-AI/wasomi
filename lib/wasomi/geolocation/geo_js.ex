defmodule Wasomi.Geolocation.GeoJS do
  @moduledoc false

  @behaviour Wasomi.Geolocation

  @timeout 500

  @impl true
  def country_code(ip) do
    case Req.get("https://get.geojs.io/v1/ip/country/#{ip}.json",
           connect_options: [timeout: @timeout],
           receive_timeout: @timeout,
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"country" => country_code}}} ->
        {:ok, country_code}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
