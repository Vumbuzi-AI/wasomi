defmodule Wasomi.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  require Logger
  alias Wasomi.Repo

  alias Wasomi.Accounts.{User, UserNotifier, UserToken}
  alias Wasomi.Paginate

  @confirmation_resend_cooldown_minutes 15

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
    user
    |> User.role_changeset(%{role: role})
    |> Repo.update()
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
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
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

  ## Magic-link login

  @magic_link_cooldown_seconds 60
  @magic_link_max_per_hour 5

  @doc """
  Emails a one-time login link to `email` if it belongs to a user.

  Always returns `:ok` — it never reveals whether the address is registered.
  Rate-limited per account (a #{@magic_link_cooldown_seconds}s cooldown and
  #{@magic_link_max_per_hour}/hour); over the limit it silently sends nothing.
  `login_url_fun` receives the raw token.
  """
  def deliver_magic_link(email, login_url_fun)
      when is_binary(email) and is_function(login_url_fun, 1) do
    normalized = email |> String.trim() |> String.downcase()

    case get_user_by_email(normalized) do
      %User{} = user ->
        if magic_link_allowed?(user) do
          {encoded_token, user_token} = UserToken.build_email_token(user, "login")
          Repo.insert!(user_token)
          UserNotifier.deliver_magic_link(user, login_url_fun.(encoded_token))
          log_magic_link("SENT", normalized, user_id: user.id)
        else
          log_magic_link("RATE_LIMITED", normalized, user_id: user.id)
        end

      nil ->
        log_magic_link("NO_ACCOUNT", normalized, [])
    end

    :ok
  end

  @doc "The user for a valid, unconsumed magic-link token (does not consume it), or `nil`."
  def get_user_by_magic_token(token) when is_binary(token) do
    case UserToken.verify_login_token_query(token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  def get_user_by_magic_token(_), do: nil

  @doc """
  Consumes a magic-link token: confirms the account if needed, deletes every
  `"login"` token for that user, and returns `{:ok, user}`. `:error` if the
  token is invalid, expired, or already used.
  """
  def login_user_by_magic_token(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_login_token_query(token),
         %User{} = user <- Repo.one(query) do
      {:ok, %{user: user}} =
        Ecto.Multi.new()
        |> Ecto.Multi.run(:user, fn _repo, _ ->
          if user.confirmed_at,
            do: {:ok, user},
            else: Repo.update(User.confirm_changeset(user))
        end)
        |> Ecto.Multi.delete_all(
          :tokens,
          UserToken.by_user_and_contexts_query(user, ["login"])
        )
        |> Repo.transaction()

      log_magic_link("CONSUMED", user.email, user_id: user.id)
      {:ok, user}
    else
      _ -> :error
    end
  end

  def login_user_by_magic_token(_), do: :error

  defp magic_link_allowed?(%User{} = user) do
    recent =
      UserToken
      |> where([t], t.user_id == ^user.id and t.context == "login")
      |> where([t], t.inserted_at > ago(1, "hour"))
      |> order_by([t], desc: t.inserted_at)
      |> Repo.all()

    cond do
      length(recent) >= @magic_link_max_per_hour ->
        false

      recent == [] ->
        true

      DateTime.diff(DateTime.utc_now(), hd(recent).inserted_at) < @magic_link_cooldown_seconds ->
        false

      true ->
        true
    end
  end

  defp log_magic_link(event, email, meta) do
    domain = email |> String.split("@") |> List.last()
    meta_str = Enum.map_join(meta, " ", fn {k, v} -> "#{k}=#{v}" end)
    Logger.info("AUDIT event=AUTH.MAGIC_LINK_#{event} email_domain=#{domain} #{meta_str}")
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
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
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
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
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
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end
end
