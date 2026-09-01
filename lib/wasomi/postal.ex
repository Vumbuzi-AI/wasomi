defmodule Wasomi.Postal do
  @moduledoc """
  Delivers application email through the MailSafi Postal HTTP API.
  """

  @default_api_url "https://postalmail.mailsafi.com/api/v1/send/message"
  @default_from "no-reply@gs1kenya.org"

  def deliver(%Swoosh.Email{} = email) do
    config = Application.get_env(:wasomi, __MODULE__, [])

    with {:ok, api_key} <- required_config(config, :api_key),
         {:ok, body, response} <- send_email(config, api_key, email) do
      {:ok, %{body: body, response: response}}
    end
  end

  defp send_email(config, api_key, email) do
    payload =
      %{
        "to" => format_recipients(email.to),
        "from" => format_from(config, email.from),
        "subject" => email.subject
      }
      |> maybe_put_body("plain_body", email.text_body)
      |> maybe_put_body("html_body", email.html_body)
      |> maybe_put_attachments(email.attachments)

    headers = [
      {"x-server-api-key", api_key},
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    req_options =
      config
      |> Keyword.get(:req_options, [])
      |> Keyword.merge(body: Jason.encode!(payload), headers: headers)

    config
    |> Keyword.get(:api_url, @default_api_url)
    |> Req.post(req_options)
    |> process_response()
  end

  defp maybe_put_body(payload, _key, nil), do: payload
  defp maybe_put_body(payload, key, body), do: Map.put(payload, key, body)

  defp maybe_put_attachments(payload, []), do: payload

  defp maybe_put_attachments(payload, attachments) do
    Map.put(payload, "attachments", Enum.map(attachments, &format_attachment/1))
  end

  defp format_attachment(%Swoosh.Attachment{} = attachment) do
    %{
      "name" => attachment.filename,
      "content_type" => attachment.content_type,
      "data" => Swoosh.Attachment.get_content(attachment, :base64)
    }
  end

  defp format_from(config, email_from) do
    configured_address = Keyword.get(config, :from, @default_from)
    {email_name, email_address} = normalize_mailbox(email_from || {"", configured_address})
    address = configured_address || email_address

    name =
      config
      |> Keyword.get(:from_name, email_name)
      |> to_string()
      |> String.trim()

    case name do
      "" -> address
      value -> "#{value} <#{address}>"
    end
  end

  defp format_recipients(recipients) do
    Enum.map(recipients, fn recipient ->
      case normalize_mailbox(recipient) do
        {"", address} -> address
        {name, address} -> "#{name} <#{address}>"
      end
    end)
  end

  defp normalize_mailbox({name, address}) do
    {name |> to_string() |> String.trim(), address |> to_string() |> String.trim()}
  end

  defp normalize_mailbox(address), do: {"", address |> to_string() |> String.trim()}

  defp required_config(config, key) do
    case config |> Keyword.get(key) |> to_string() |> String.trim() do
      "" -> {:error, {:missing_config, key}}
      value -> {:ok, value}
    end
  end

  defp process_response({:ok, %{status: status, body: body} = response})
       when status in 200..299 do
    {:ok, body, response}
  end

  defp process_response({:ok, %{status: status, body: body}}) do
    {:error, {:postal_error, status, body}}
  end

  defp process_response({:error, reason}), do: {:error, reason}
end
