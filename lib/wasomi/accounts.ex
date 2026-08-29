defmodule Wasomi.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Wasomi.Repo

  alias Wasomi.Accounts.{AuditEvent, User, UserNotifier, UserToken}
  alias Wasomi.Paginate

  @confirmation_resend_cooldown_minutes 15
  @sensitive_audit_keys MapSet.new(~w(
    _csrf_token
    current_password
    password
    password_confirmation
    remember_me
    token
    user_token
  ))

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Records an append-only account audit event.

  Metadata is sanitized before insert: known secret-bearing keys are dropped
  recursively and long strings are capped so request payloads cannot bloat the
  row or leak credentials into the audit trail.
  """
  def record_account_audit_event(user_or_nil, event, attrs \\ [])

  def record_account_audit_event(%User{} = user, event, attrs) do
    attrs
    |> audit_attrs_to_keyword()
    |> Keyword.put(:user_id, user.id)
    |> insert_account_audit_event(event)
  end

  def record_account_audit_event(nil, event, attrs) do
    attrs
    |> audit_attrs_to_keyword()
    |> insert_account_audit_event(event)
  end

  @doc """
  Lists audit events for one account, newest first.

  `:limit` is clamped to `1..200`; a non-integer is ignored and the default
  (50) is used.
  """
  def list_account_audit_events(%User{} = user, opts \\ []) do
    limit =
      case Keyword.get(opts, :limit, 50) do
        limit when is_integer(limit) -> limit |> max(1) |> min(200)
        _ -> 50
      end

    AuditEvent
    |> where([event], event.user_id == ^user.id)
    |> order_by([event], desc: event.inserted_at, desc: event.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns pseudonymised, safe-to-store metadata for an attempted email address.

  The raw address is never persisted. `email_fingerprint` is a keyed HMAC
  (not a bare hash): it lets repeated attempts against the same address be
  correlated, but a database-only compromise cannot confirm which address a
  fingerprint belongs to without also holding the app secret. `email_domain`
  is kept in the clear because it carries operational value (spotting a
  targeted domain) at low individual-privacy cost.
  """
  def audit_email_metadata(email) when is_binary(email) do
    normalized = email |> String.trim() |> String.downcase()

    %{
      "email_fingerprint" => email_fingerprint(normalized),
      "email_domain" => email_domain(normalized)
    }
  end

  def audit_email_metadata(_email), do: %{}

  defp email_fingerprint(normalized_email) do
    :hmac
    |> :crypto.mac(
      :sha256,
      Application.fetch_env!(:wasomi, :audit_fingerprint_key),
      normalized_email
    )
    |> Base.encode16(case: :lower)
  end

  @doc """
  Returns the list of users, newest first, optionally filtered.

  ## Options

    * `:role` - only users with this role (`:learner`, `:admin`).
    * `:search` - case-insensitive match against name, email, or phone.

  """
  def list_users(opts \\ []) do
    User
    |> scope_role(Keyword.get(opts, :role))
    |> scope_search(Keyword.get(opts, :search))
    |> order_by([u], desc: u.inserted_at, desc: u.id)
    |> Repo.all()
  end

  @doc """
  Returns a `Wasomi.Paginate.Page` of users, same `:role`/`:search`
  filtering as `list_users/1` plus `:page`/`:page_size`.
  """
  def list_users_page(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 10)

    User
    |> scope_role(Keyword.get(opts, :role))
    |> scope_search(Keyword.get(opts, :search))
    |> order_by([u], desc: u.inserted_at, desc: u.id)
    |> Paginate.paginate(page, page_size)
  end

  @doc """
  Counts users, optionally scoped to a role.
  """
  def count_users(role \\ nil) do
    User
    |> scope_role(role)
    |> Repo.aggregate(:count)
  end

  defp scope_role(query, nil), do: query
  defp scope_role(query, role), do: where(query, [u], u.role == ^role)

  defp scope_search(query, search) when search in [nil, ""], do: query

  defp scope_search(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [u],
      ilike(u.name, ^pattern) or ilike(u.email, ^pattern) or ilike(u.phone, ^pattern)
    )
  end

  @doc """
  Updates a user's role through the administrative changeset.
  """
  def update_user_role(%User{} = user, role) do
    old_role = user.role
    changeset = User.role_changeset(user, %{role: role})

    if Map.has_key?(changeset.changes, :role) do
      Ecto.Multi.new()
      |> Ecto.Multi.update(:user, changeset)
      |> put_account_audit_event(:audit_event, user, :role_changed,
        metadata: %{old_role: old_role, new_role: role}
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{user: user}} -> {:ok, user}
        {:error, :user, changeset, _} -> {:error, changeset}
        {:error, :audit_event, changeset, _} -> raise_account_audit_failure!(changeset)
      end
    else
      Repo.update(changeset)
    end
  end

  @doc """
  Suggests an email typo correction if the domain closely resembles a known provider.
  """
  defdelegate suggest_email_typo(email), to: Wasomi.Accounts.EmailTypo, as: :suggest

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.registration_changeset(%User{}, attrs))
    |> Ecto.Multi.insert(:audit_event, fn %{user: user} ->
      account_audit_event_changeset(user, :registered)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, :audit_event, changeset, _} -> raise_account_audit_failure!(changeset)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
    |> put_account_audit_event(:audit_event, user, :email_changed,
      metadata: %{
        old_email: audit_email_metadata(user.email),
        new_email: audit_email_metadata(email)
      }
    )
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> put_account_audit_event(:audit_event, user, :password_changed)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, :audit_event, changeset, _} -> raise_account_audit_failure!(changeset)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user's private profile
  (bio, country, occupation, avatar).

  ## Examples

      iex> change_user_profile(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_profile(user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Updates the user's private profile.

  ## Examples

      iex> update_user_profile(user, %{bio: "..."})
      {:ok, %User{}}

      iex> update_user_profile(user, %{country: "Not a country"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_profile(%User{} = user, attrs) do
    changeset = User.profile_changeset(user, attrs)
    changed_fields = Map.keys(changeset.changes)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update(:user, changeset)

    multi =
      if changed_fields == [] do
        multi
      else
        put_account_audit_event(multi, :audit_event, user, :profile_updated,
          metadata: %{changed_fields: changed_fields}
        )
      end

    multi
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, :audit_event, changeset, _} -> raise_account_audit_failure!(changeset)
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/users/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    cond do
      user.confirmed_at ->
        {:error, :already_confirmed}

      recent_confirmation_token?(user) ->
        {:error, :rate_limited}

      true ->
        {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
        Repo.insert!(user_token)
        UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  defp recent_confirmation_token?(%User{} = user) do
    UserToken.by_user_and_contexts_query(user, ["confirm"])
    |> where([token], token.inserted_at > ago(@confirmation_resend_cooldown_minutes, "minute"))
    |> limit(1)
    |> Repo.exists?()
  end

  @doc """
  Looks up the user a confirmation token belongs to, without consuming it.

  Read-only — unlike `confirm_user/1`, this doesn't mark the account
  confirmed or delete the token, so it's safe to call from a plain page
  view (e.g. a link-preview/security scanner that pre-fetches the
  confirmation URL before the recipient opens it).
  """
  def get_user_by_confirmation_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      Wasomi.Notifications.deliver_welcome(user)
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
    |> put_account_audit_event(:audit_event, user, :email_confirmed)
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> put_account_audit_event(:audit_event, user, :password_reset)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, :audit_event, changeset, _} -> raise_account_audit_failure!(changeset)
    end
  end

  defp insert_account_audit_event(attrs, event) do
    attrs
    |> account_audit_event_attrs(event)
    |> then(&AuditEvent.changeset(%AuditEvent{}, &1))
    |> Repo.insert()
  end

  defp put_account_audit_event(multi, name, user, event, attrs \\ []) do
    Ecto.Multi.insert(multi, name, fn _changes ->
      account_audit_event_changeset(user, event, attrs)
    end)
  end

  defp account_audit_event_changeset(user_or_nil, event, attrs \\ []) do
    user_or_nil
    |> account_audit_event_attrs(event, attrs)
    |> then(&AuditEvent.changeset(%AuditEvent{}, &1))
  end

  defp account_audit_event_attrs(%User{} = user, event, attrs) do
    attrs
    |> Keyword.put(:user_id, user.id)
    |> account_audit_event_attrs(event)
  end

  defp account_audit_event_attrs(nil, event, attrs) do
    account_audit_event_attrs(attrs, event)
  end

  defp account_audit_event_attrs(attrs, event) do
    attrs = audit_attrs_to_keyword(attrs)
    metadata = attrs |> Keyword.get(:metadata, %{}) |> scrub_audit_metadata()

    %{
      event: event,
      metadata: metadata,
      ip_address: attrs |> Keyword.get(:ip_address) |> blank_to_nil(),
      user_agent: attrs |> Keyword.get(:user_agent) |> truncate_string(512),
      user_id: Keyword.get(attrs, :user_id)
    }
  end

  defp scrub_audit_metadata(metadata) when is_map(metadata) do
    Enum.reduce(metadata, %{}, fn {key, value}, acc ->
      key = to_string(key)

      if MapSet.member?(@sensitive_audit_keys, String.downcase(key)) do
        acc
      else
        Map.put(acc, key, scrub_audit_value(value))
      end
    end)
  end

  defp scrub_audit_metadata(_metadata), do: %{}

  defp scrub_audit_value(nil), do: nil
  defp scrub_audit_value(value) when is_boolean(value), do: value
  defp scrub_audit_value(value) when is_number(value), do: value
  defp scrub_audit_value(value) when is_binary(value), do: truncate_string(value, 512)
  defp scrub_audit_value(value) when is_atom(value), do: Atom.to_string(value)
  # A struct (%DateTime{}, a schema, …) is never an intended metadata value —
  # recursing would expose its internal fields. Drop it rather than serialise.
  defp scrub_audit_value(%_{}), do: "[filtered]"
  defp scrub_audit_value(value) when is_map(value), do: scrub_audit_metadata(value)
  defp scrub_audit_value(value) when is_list(value), do: Enum.map(value, &scrub_audit_value/1)
  defp scrub_audit_value(_value), do: "[filtered]"

  defp audit_attrs_to_keyword(attrs) when is_map(attrs), do: Map.to_list(attrs)
  defp audit_attrs_to_keyword(attrs) when is_list(attrs), do: attrs
  defp audit_attrs_to_keyword(_attrs), do: []

  # An audit-event insert failing inside an account-change transaction is a
  # system fault, not user-correctable input — surface it loudly instead of
  # returning an `AuditEvent` changeset that callers would mistake for a
  # validation error on the account form.
  defp raise_account_audit_failure!(changeset) do
    raise "account audit event could not be recorded: #{inspect(changeset.errors)}"
  end

  defp email_domain(email) do
    case String.split(email, "@", parts: 2) do
      [_local, domain] -> domain
      _ -> nil
    end
  end

  defp truncate_string(nil, _max_length), do: nil

  defp truncate_string(value, max_length) when is_binary(value) do
    String.slice(value, 0, max_length)
  end

  defp blank_to_nil(value) when value in ["", nil], do: nil
  defp blank_to_nil(value), do: value
end
