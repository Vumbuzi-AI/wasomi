defmodule Wasomi.Receipts do
  @moduledoc """
  Learner-facing payment receipts: the list a learner sees under
  "Receipts", and the downloadable PDF for a single successful payment.

  Thin layer over `Wasomi.Payments` — it owns nothing in the database, only
  the presentation of a payment as a receipt.
  """

  alias Wasomi.Accounts.User
  alias Wasomi.Certificates.Branding
  alias Wasomi.Payments
  alias Wasomi.Payments.Payment
  alias Wasomi.Repo

  @doc "A learner's successful payments, newest first, course preloaded."
  defdelegate list_for_user(user), to: Payments, as: :list_receipts_for_user

  @doc "A paginated `Wasomi.Paginate.Page` of the same, for the receipts screen."
  defdelegate page_for_user(user, opts), to: Payments, as: :list_receipts_for_user_page

  @doc """
  The learner's own successful payment for `payment_id`, or `nil` if it
  doesn't exist, isn't theirs, or isn't paid.
  """
  def get_for_user(%User{id: user_id}, payment_id) do
    with {:ok, id} when not is_nil(id) <- Ecto.Type.cast(:integer, payment_id),
         %Payment{user_id: ^user_id, status: :successful} = payment <- Payments.get_payment(id) do
      Repo.preload(payment, :course)
    else
      _other -> nil
    end
  end

  @doc """
  Renders `payment` as receipt PDF bytes. Returns `{:error, :not_found}`
  when the payment isn't a receipt the given user may download.
  """
  def pdf_for(%User{} = user, payment_id) do
    case get_for_user(user, payment_id) do
      nil -> {:error, :not_found}
      payment -> renderer().render(assigns_for(user, payment))
    end
  end

  @doc "The filename to offer for a receipt download."
  def filename(%Payment{provider_reference: reference}) do
    slug = reference |> to_string() |> String.replace(~r/[^A-Za-z0-9]+/, "-")
    "wasomi-receipt-#{slug}.pdf"
  end

  defp assigns_for(%User{} = user, %Payment{} = payment) do
    branding = Application.get_env(:wasomi, :certificate_branding, [])

    %{
      issuer_name: Branding.issuer_name(),
      address_lines: Keyword.get(branding, :address_lines, []) |> Enum.reject(&(&1 in [nil, ""])),
      issuer_email: branding[:email],
      issuer_phone: branding[:phone],
      issuer_website: branding[:website],
      receipt_no: "WSM-" <> String.pad_leading(to_string(payment.id), 5, "0"),
      reference: payment.provider_reference,
      issued_on: format_datetime(payment.paid_at),
      billed_to_name: user.name || user.email,
      billed_to_email: user.email,
      course_title: payment.course.title,
      amount: Payments.format_amount(payment),
      tax: Payments.format_minor(0, payment.currency),
      payment_method: provider_label(payment.provider)
    }
  end

  defp provider_label(:paystack), do: "Paystack"
  defp provider_label(:mpesa), do: "M-Pesa"
  defp provider_label(other), do: other |> to_string() |> String.capitalize()

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%B %-d, %Y · %-I:%M %p UTC")

  defp format_datetime(_), do: "—"

  defp renderer, do: Application.fetch_env!(:wasomi, :receipt_renderer)
end
