defmodule Wasomi.Payments.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "payments" do
    field :status, Ecto.Enum, values: [:pending, :successful, :failed], default: :pending
    field :currency, :string
    field :provider, Ecto.Enum, values: [:mpesa, :paystack]
    field :provider_reference, :string
    field :amount_minor, :integer
    field :phone, :string
    field :raw_payload, :map
    field :paid_at, :utc_datetime
    belongs_to :user, Wasomi.Accounts.User
    belongs_to :course, Wasomi.Catalog.Course
    belongs_to :enrollment, Wasomi.Enrollments.Enrollment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [
      :provider,
      :provider_reference,
      :amount_minor,
      :currency,
      :phone,
      :status,
      :raw_payload,
      :paid_at,
      :user_id,
      :course_id,
      :enrollment_id
    ])
    |> update_change(:phone, &Wasomi.Accounts.User.normalize_phone/1)
    |> validate_format(:phone, ~r/^2547\d{8}$/,
      message: "must be a valid Kenyan mobile number (07XXXXXXXX)"
    )
    |> validate_required([
      :provider,
      :provider_reference,
      :amount_minor,
      :currency,
      :status,
      :user_id,
      :course_id,
      :enrollment_id
    ])
    |> validate_number(:amount_minor, greater_than: 0)
    |> validate_format(:currency, ~r/^[A-Z]{3}$/)
    |> validate_paid_state()
    |> assoc_constraint(:user)
    |> assoc_constraint(:course)
    |> assoc_constraint(:enrollment)
    |> unique_constraint(:provider_reference)
    |> check_constraint(:phone, name: :payments_phone_must_be_normalized)
    |> check_constraint(:provider, name: :payments_provider_must_be_valid)
    |> check_constraint(:status, name: :payments_status_must_be_valid)
    |> check_constraint(:amount_minor, name: :payments_amount_must_be_positive)
    |> check_constraint(:paid_at, name: :payments_paid_at_must_match_status)
  end

  defp validate_paid_state(changeset) do
    case {get_field(changeset, :status), get_field(changeset, :paid_at)} do
      {:successful, nil} ->
        add_error(changeset, :paid_at, "is required for a successful payment")

      {status, %DateTime{}} when status != :successful ->
        add_error(changeset, :paid_at, "must be empty unless payment is successful")

      _ ->
        changeset
    end
  end
end
