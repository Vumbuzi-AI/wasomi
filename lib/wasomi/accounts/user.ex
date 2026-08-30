defmodule Wasomi.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wasomi.Accounts.Countries

  schema "users" do
    field :name, :string
    field :email, :string
    field :phone, :string
    field :password, :string, virtual: true, redact: true
    field :password_confirmation, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :current_password, :string, virtual: true, redact: true
    field :confirmed_at, :utc_datetime
    field :role, Ecto.Enum, values: [:learner, :admin], default: :learner
    field :bio, :string
    field :country, :string
    field :occupation, :string
    field :avatar_key, :string
    field :headline, :string
    field :organization, :string
    field :industry, :string
    field :experience_level, Ecto.Enum, values: [:student, :entry, :mid, :senior, :lead_executive]

    field :learning_goal, Ecto.Enum,
      values: [
        :career_advancement,
        :career_switch,
        :certification,
        :upskilling,
        :personal_interest
      ]

    timestamps(type: :utc_datetime)
  end

  @bio_max_length 500
  @occupation_max_length 160
  @headline_max_length 120
  @organization_max_length 160

  @industries [
    "Technology & Software",
    "Supply Chain & Logistics",
    "Banking & Financial Services",
    "Healthcare & Pharmaceuticals",
    "Manufacturing & Engineering",
    "Retail & E-commerce",
    "Education & Training",
    "Agriculture & Agribusiness",
    "Public Sector & Non-Profit",
    "Consulting & Professional Services",
    "Energy & Utilities",
    "Other"
  ]

  @doc "The fixed list of industries offered on the learner profile's `industry` dropdown."
  def industries, do: @industries

  @doc """
  A user changeset for registration.

  It is important to validate the length of both email and password.
  Otherwise databases may truncate the email without warnings, which
  could lead to unpredictable or insecure behaviour. Long passwords may
  also be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.

    * `:validate_email` - Validates the uniqueness of the email, in case
      you don't want to validate the uniqueness of the email (like when
      using this changeset for validations on a LiveView form before
      submitting the form), this option can be set to `false`.
      Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:name, :email, :password, :password_confirmation, :phone])
    |> validate_name()
    |> validate_email(opts)
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
    |> validate_optional_phone()
  end

  @e164_format ~r/^\+[1-9]\d{6,14}$/

  @doc """
  Casts an optional phone number stored in E.164 form (`+<country><number>`).

  Blank input clears the field; a present value must look like E.164. The
  `users_phone_must_be_e164` DB check and the `users_phone_index` unique index
  are surfaced as friendly changeset errors rather than raising.
  """
  def validate_optional_phone(changeset) do
    changeset
    |> update_change(:phone, &normalize_phone_input/1)
    |> validate_format(:phone, @e164_format, message: "doesn't look like a valid phone number")
    |> unique_constraint(:phone,
      name: :users_phone_index,
      message: "is already registered to another account"
    )
    |> check_constraint(:phone,
      name: :users_phone_must_be_e164,
      message: "doesn't look like a valid phone number"
    )
  end

  # The JS widget submits clean E.164, but a hand-typed / no-JS / pasted value
  # can carry spaces, dashes or brackets — strip them so a real number isn't
  # rejected on formatting alone. A blank result clears the optional field.
  defp normalize_phone_input(value) when is_binary(value) do
    case String.replace(value, ~r/[\s()\-.]/, "") do
      "" -> nil
      stripped -> stripped
    end
  end

  defp normalize_phone_input(value), do: value

  @doc """
  Changes a user's role through an explicit administrative code path.

  Registration deliberately does not cast `role`, so public sign-up can never
  promote a learner to an administrator.
  """
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> check_constraint(:role, name: :users_role_must_be_valid)
  end

  @doc """
  A user changeset for editing the learner's private profile: headline,
  bio, country, organization, industry, occupation, experience level,
  learning goal, and avatar.

  This is a self-editable, private surface — none of these fields are
  required, and none are exposed to other learners through any existing
  query. `country` and `industry` are each constrained to a fixed list
  rather than accepted as free text; `experience_level` and
  `learning_goal` are enums for the same reason.
  """
  @profile_select_fields ~w(country industry experience_level learning_goal)a

  def profile_changeset(user, attrs) do
    user
    |> cast(blank_selects_to_nil(attrs), [
      :headline,
      :bio,
      :country,
      :organization,
      :industry,
      :occupation,
      :experience_level,
      :learning_goal,
      :avatar_key
    ])
    |> validate_length(:headline, max: @headline_max_length)
    |> validate_length(:bio, max: @bio_max_length)
    |> validate_length(:organization, max: @organization_max_length)
    |> validate_length(:occupation, max: @occupation_max_length)
    |> validate_inclusion(:country, Countries.list(), message: "is not a supported country")
    |> validate_inclusion(:industry, @industries, message: "is not a supported industry")
  end

  # "" from an unselected <select> is invalid for Ecto.Enum (not "unset") — normalize to nil
  defp blank_selects_to_nil(attrs) do
    Enum.reduce(@profile_select_fields, attrs, fn field, attrs ->
      attrs
      |> blank_key_to_nil(field)
      |> blank_key_to_nil(Atom.to_string(field))
    end)
  end

  defp blank_key_to_nil(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, ""} -> Map.put(attrs, key, nil)
      _ -> attrs
    end
  end

  defp validate_name(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 160)
  end

  @doc """
  Normalises a Kenyan MSISDN to the `2547XXXXXXXX` form used for M-Pesa.

  Accepts common input shapes (`07XXXXXXXX`, `+2547XXXXXXXX`, `7XXXXXXXX`)
  and strips spaces, hyphens and a leading `+`.
  """
  def normalize_phone(phone) when is_binary(phone) do
    digits = phone |> String.replace(~r/[\s\-+]/, "")

    cond do
      String.match?(digits, ~r/^0(7\d{8})$/) -> "254" <> String.slice(digits, 1..-1//1)
      String.match?(digits, ~r/^7\d{8}$/) -> "254" <> digits
      true -> digits
    end
  end

  def normalize_phone(phone), do: phone

  @doc """
  Validates that a phone string is a normalised Kenyan M-Pesa number.

  Shared by the checkout flow, which collects the number used for the
  payment prompt.
  """
  def validate_mpesa_phone(changeset, field) do
    changeset
    |> update_change(field, &normalize_phone/1)
    |> validate_required([field])
    |> validate_format(field, ~r/^2547\d{8}$/,
      message: "must be a valid Kenyan mobile number (07XXXXXXXX)"
    )
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 6, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
      |> delete_change(:password_confirmation)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Wasomi.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the email.

  It requires the email to change otherwise an error is added.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  @doc """
  A user changeset for changing the password.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Wasomi.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password) do
    changeset = cast(changeset, %{current_password: password}, [:current_password])

    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end
end
