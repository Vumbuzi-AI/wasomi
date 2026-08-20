defmodule Wasomi.Certificates.Branding do
  @moduledoc """
  Organisation-level certificate branding: the logo, postal/contact details and
  social handles printed down the certificate's left rail.

  These are properties of the institution, not of a course, so they live in
  application config rather than on `courses` — every certificate the app
  issues shares them. Per-course values (issuer name, signatories) stay on the
  course record.

  Configure in `config/config.exs`:

      config :wasomi, :certificate_branding,
        logo_path: "images/logo.png",
        address_lines: ["5th Floor, Nextgen Mall", "P.O. Box 3243-00200", "Nairobi, Kenya"],
        phone: "+254 700 000 000",
        email: "info@example.org",
        website: "www.example.org",
        socials: ["Facebook", "LinkedIn", "YouTube"]

  Anything left unset simply doesn't render — the rail collapses around it
  rather than printing an empty label or a placeholder.
  """

  @doc """
  Returns the branding assigns the certificate template expects.

  `logo_data_uri` is a base64 `data:` URI rather than a URL on purpose. The
  PDF renderer hands Chrome a bare HTML string with no base URL, so a relative
  `/images/logo.png` has nothing to resolve against and an absolute URL makes
  the render depend on the network (and on the asset being publicly reachable,
  which it isn't during a local `mix test`). An inlined image can't fail to
  load.
  """
  def assigns do
    config = Application.get_env(:wasomi, :certificate_branding, [])

    %{
      logo_data_uri: config |> Keyword.get(:logo_path) |> logo_data_uri(),
      address_lines: config |> Keyword.get(:address_lines, []) |> compact(),
      phone: config |> Keyword.get(:phone) |> presence(),
      email: config |> Keyword.get(:email) |> presence(),
      website: config |> Keyword.get(:website) |> presence(),
      socials: config |> Keyword.get(:socials, []) |> compact()
    }
  end

  defp logo_data_uri(nil), do: nil

  defp logo_data_uri(path) when is_binary(path) do
    full_path = Path.join([:code.priv_dir(:wasomi), "static", path])

    case File.read(full_path) do
      {:ok, binary} -> "data:#{mime_type(path)};base64," <> Base.encode64(binary)
      # A missing logo shouldn't take the whole certificate down with it —
      # the template falls back to the issuer name set in wordmark type.
      {:error, _reason} -> nil
    end
  end

  defp mime_type(path) do
    case path |> Path.extname() |> String.downcase() do
      ".svg" -> "image/svg+xml"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      _ -> "image/png"
    end
  end

  defp compact(values) when is_list(values), do: Enum.filter(values, &presence/1)
  defp compact(_values), do: []

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_value), do: nil
end
