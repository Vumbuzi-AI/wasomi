defmodule Wasomi.Paystack do
  @moduledoc """
  Paystack hosted-checkout adapter.
  """

  @behaviour Wasomi.Payments.Provider

  alias Wasomi.Payments.Payment

  @impl true
  def initiate(%Payment{} = payment) do
    payment = Wasomi.Repo.preload(payment, :user)

    request(:post, "/transaction/initialize",
      json:
        %{
          email: payment.user.email,
          amount: payment.amount_minor,
          reference: payment.provider_reference,
          callback_url: callback_url()
        }
        |> maybe_put_phone(payment.phone)
    )
    |> normalize_response()
  end

  # Surfaces the learner-chosen M-Pesa number to Paystack so the mobile-money
  # prompt is sent to it. Paystack prefills the checkout from the metadata.
  defp maybe_put_phone(params, phone) when is_binary(phone) and phone != "" do
    params
    |> Map.put(:phone, phone)
    |> Map.put(:metadata, %{phone: phone})
  end

  defp maybe_put_phone(params, _phone), do: params

  @impl true
  def verify(reference) when is_binary(reference) do
    request(:get, "/transaction/verify/#{URI.encode(reference)}")
    |> normalize_response()
  end

  def callback_url do
    Application.fetch_env!(:wasomi, :paystack_callback_url)
  end

  defp request(method, path, options \\ []) do
    Req.request(
      [
        method: method,
        url: api_url() <> path,
        headers: [
          {"authorization", "Bearer #{secret_key()}"},
          {"content-type", "application/json"}
        ],
        retry: :transient,
        max_retries: 2,
        receive_timeout: 15_000
      ] ++ options
    )
  end

  defp normalize_response({:ok, %{status: status, body: %{"status" => true, "data" => data}}})
       when status in 200..299,
       do: {:ok, data}

  defp normalize_response({:ok, %{body: body}}) when is_map(body),
    do: {:error, Map.get(body, "message", "Paystack request failed")}

  defp normalize_response({:ok, %{status: status}}),
    do: {:error, {:unexpected_paystack_response, status}}

  defp normalize_response({:error, reason}), do: {:error, reason}

  defp api_url, do: Application.fetch_env!(:wasomi, :paystack_api_url)

  defp secret_key do
    "sk_test_7267bf7b9b38cd9798c6328f7e0b3cc5a264f4aa"
  end
end
