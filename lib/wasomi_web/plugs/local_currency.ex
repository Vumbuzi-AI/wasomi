defmodule WasomiWeb.Plugs.LocalCurrency do
  @moduledoc """
  Resolves the user's local currency based on their IP address and stores it in the session.
  """
  import Plug.Conn
  import Bitwise

  @native_currencies ["KES", "NGN", "ZAR", "GHS", "UGX", "RWF", "EGP"]
  @europe_countries [
    "AT",
    "BE",
    "BG",
    "HR",
    "CY",
    "CZ",
    "DK",
    "EE",
    "FI",
    "FR",
    "DE",
    "GR",
    "HU",
    "IE",
    "IT",
    "LV",
    "LT",
    "LU",
    "MT",
    "NL",
    "PL",
    "PT",
    "RO",
    "SK",
    "SI",
    "ES",
    "SE",
    "AL",
    "AD",
    "AM",
    "BY",
    "BA",
    "FO",
    "GE",
    "GI",
    "IS",
    "IM",
    "XK",
    "LI",
    "MK",
    "MD",
    "MC",
    "ME",
    "NO",
    "RU",
    "SM",
    "RS",
    "CH",
    "TR",
    "UA",
    "GB",
    "VA"
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :display_currency) do
      conn
    else
      country_code = get_country_code(conn)
      currency = resolve_display_currency(country_code)
      put_session(conn, :display_currency, currency)
    end
  end

  defp get_country_code(conn) do
    default_country = Application.get_env(:wasomi, :default_country, "US")

    # Try Cloudflare header first
    case get_req_header(conn, "cf-ipcountry") do
      [country | _] when country not in ["XX", "T1"] ->
        country

      _ ->
        case conn.remote_ip do
          nil ->
            default_country

          ip_tuple ->
            if private_ip?(ip_tuple) do
              # Default for local dev or internal networks
              default_country
            else
              ip = ip_tuple |> :inet.ntoa() |> to_string() |> URI.encode_www_form()

              # Fallback to IP Geolocation API using HTTPS
              case Req.get("https://get.geojs.io/v1/ip/country/#{ip}.json",
                     receive_timeout: 1000,
                     retry: false
                   ) do
                {:ok, %{status: 200, body: %{"country" => code}}} -> code
                _ -> default_country
              end
            end
        end
    end
  end

  defp private_ip?({10, _, _, _}), do: true
  defp private_ip?({192, 168, _, _}), do: true
  defp private_ip?({172, second, _, _}) when second in 16..31, do: true
  defp private_ip?({127, _, _, _}), do: true
  defp private_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  # IPv6 Unique Local Addresses (fc00::/7) and Link-Local (fe80::/10)
  defp private_ip?({first, _, _, _, _, _, _, _}) when (first &&& 0xFE00) == 0xFC00, do: true
  defp private_ip?({first, _, _, _, _, _, _, _}) when (first &&& 0xFFC0) == 0xFE80, do: true
  defp private_ip?(_), do: false

  defp resolve_display_currency(nil), do: "USD"

  defp resolve_display_currency(country_code) do
    # Try to find the territory's native currency
    native_currency =
      case Cldr.Currency.current_currency_for_territory(country_code) do
        {:ok, currency} -> to_string(currency)
        _ -> nil
      end

    cond do
      native_currency in @native_currencies -> native_currency
      country_code in @europe_countries -> "EUR"
      true -> "USD"
    end
  end
end
