defmodule Wasomi.Certificates.Branding do
  @moduledoc """
  Organisation-level certificate branding: the issuer name, logo, postal/
  contact details and social handles printed on every certificate.

  These are properties of the institution issuing the certificates, not of a
  course, so they live in application config rather than on `courses` —
  every certificate the app issues shares them. Per-course values (the
  signatories who sign it) stay on the course record.

  Configure in `config/config.exs`:

      config :wasomi, :certificate_branding,
        issuer_name: "GS1 Kenya",
        logo_path: "images/logo.png",
        address_lines: ["5th Floor, Nextgen Mall", "P.O. Box 3243-00200", "Nairobi, Kenya"],
        phone: "+254 700 000 000",
        email: "info@example.org",
        website: "www.example.org",
        socials: [{"Facebook", "https://facebook.com/example"}, {"LinkedIn", nil}]

  Anything left unset simply doesn't render — the rail collapses around it
  rather than printing an empty label or a placeholder.
  """

  @default_issuer_name "GS1 Kenya"
  @icon_strip_path "images/cert-vector.png"
  @seal_path "images/seal.png"

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
      issuer_name: issuer_name(config),
      logo_data_uri: config |> Keyword.get(:logo_path) |> asset_data_uri(),
      address_lines: config |> Keyword.get(:address_lines, []) |> compact(),
      phone: config |> Keyword.get(:phone) |> presence(),
      email: config |> Keyword.get(:email) |> presence(),
      website: config |> Keyword.get(:website) |> presence(),
      socials: config |> Keyword.get(:socials, []) |> compact_socials(),
      icon_strip_data_uri: asset_data_uri(@icon_strip_path),
      seal_data_uri: asset_data_uri(@seal_path)
    }
  end

  @doc """
  Returns just the configured issuer name, without the logo/icon-strip file
  reads the rest of `assigns/0` does.
  """
  def issuer_name do
    :wasomi
    |> Application.get_env(:certificate_branding, [])
    |> issuer_name()
  end

  defp issuer_name(config),
    do: config |> Keyword.get(:issuer_name) |> presence() || @default_issuer_name

  defp asset_data_uri(nil), do: nil

  defp asset_data_uri(path) when is_binary(path) do
    full_path = Path.join([:code.priv_dir(:wasomi), "static", path])

    case File.read(full_path) do
      {:ok, binary} -> "data:#{mime_type(path)};base64," <> Base.encode64(binary)
      # A missing asset shouldn't take the whole certificate down with it —
      # the template falls back to the issuer name (for the logo) or simply
      # omits the element (for the icon strip and seal).
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

  # Each entry is `{label, url}` — url is optional (renders the label as
  # plain, non-clickable text when absent), label is not.
  defp compact_socials(values) when is_list(values) do
    values
    |> Enum.map(fn {label, url} -> {presence(label), presence(url)} end)
    |> Enum.filter(fn {label, _url} -> not is_nil(label) end)
  end

  defp compact_socials(_values), do: []

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_value), do: nil
end
