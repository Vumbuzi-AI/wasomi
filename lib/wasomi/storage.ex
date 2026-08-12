defmodule Wasomi.Storage do
  alias Wasomi.Accounts.User

  @type upload :: %{
          key: String.t(),
          url: String.t(),
          public_url: String.t() | nil,
          expires_in: pos_integer()
        }

  @callback presign_upload(User.t(), map()) :: {:ok, upload()} | {:error, term()}
  @callback delete_upload(User.t(), String.t()) :: :ok | {:error, term()}
  @callback download_url(String.t()) :: {:ok, String.t()} | {:error, term()}

  def presign_upload(user, attrs), do: presign_upload(user, attrs, configured_adapter())

  def presign_upload(%User{role: :admin} = user, attrs, adapter) do
    adapter.presign_upload(user, attrs)
  end

  def presign_upload(_user, _attrs, _adapter), do: {:error, :forbidden}

  def delete_upload(user, key), do: delete_upload(user, key, configured_adapter())

  def delete_upload(%User{role: :admin} = user, key, adapter) when is_binary(key) do
    adapter.delete_upload(user, key)
  end

  def delete_upload(_user, _key, _adapter), do: {:error, :forbidden}

  def download_url(key), do: download_url(key, configured_adapter())

  def download_url(key, adapter) when is_binary(key) and key != "" do
    adapter.download_url(key)
  end

  def download_url(_key, _adapter), do: {:error, :invalid_storage_key}

  def configured_adapter do
    Application.get_env(:wasomi, :storage_provider, Wasomi.Storage.R2)
  end
end
