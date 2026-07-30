defmodule Wasomi.Storage do
  alias Wasomi.Accounts.User

  @type upload :: %{
          key: String.t(),
          url: String.t(),
          public_url: String.t(),
          expires_in: pos_integer()
        }

  @callback presign_upload(User.t(), map()) :: {:ok, upload()} | {:error, term()}

  def presign_upload(user, attrs, adapter \\ configured_adapter())

  def presign_upload(%User{role: :admin} = user, attrs, adapter) do
    adapter.presign_upload(user, attrs)
  end

  def presign_upload(_user, _attrs, _adapter), do: {:error, :forbidden}

  def configured_adapter do
    Application.get_env(:wasomi, :storage_provider, Wasomi.Storage.R2)
  end
end
