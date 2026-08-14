defmodule WasomiWeb.Plugs.LocalCurrency do
  @moduledoc """
  Resolves the user's local currency based on their IP address and stores it in the session.
  """
  import Plug.Conn

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
    # Try Cloudflare header first
    case get_req_header(conn, "cf-ipcountry") do
      [country | _] when country not in ["XX", "T1"] ->
        country

      _ ->
        # Fallback to IP Geolocation API
        ip = conn.remote_ip |> :inet.ntoa() |> to_string()

        # Don't query local IPs
        if ip in ["127.0.0.1", "::1"] do
          # Default for local dev
          "KE"
        else
          case Req.get("http://ip-api.com/json/#{ip}") do
            {:ok, %{status: 200, body: %{"status" => "success", "countryCode" => code}}} -> code
            _ -> "KE"
          end
        end
    end
  end

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
