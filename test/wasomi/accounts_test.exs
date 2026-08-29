defmodule Wasomi.AccountsTest do
  use Wasomi.DataCase

  alias Wasomi.Accounts

  import Wasomi.AccountsFixtures
  import Swoosh.TestAssertions
  alias Wasomi.Accounts.{AuditEvent, Countries, User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires identity, email and password to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"],
               name: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} =
        Accounts.register_user(%{
          name: "Test User",
          email: "not valid",
          password: "short"
        })

      assert %{
               email: ["must have the @ sign and no spaces"],
               password: ["should be at least 6 character(s)"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long, password: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users with a hashed password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
      assert user.role == :learner

      assert [%AuditEvent{event: :registered, user_id: user_id}] =
               Accounts.list_account_audit_events(user)

      assert user_id == user.id
    end

    test "does not allow registration to set an admin role" do
      {:ok, user} = Accounts.register_user(valid_user_attributes(role: :admin))
      assert user.role == :learner
    end
  end

  describe "change_user_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_registration(%User{})
      assert Enum.sort(changeset.required) == Enum.sort([:name, :password, :email])
    end

    test "allows fields to be set" do
      email = unique_user_email()
      password = valid_user_password()

      changeset =
        Accounts.change_user_registration(
          %User{},
          valid_user_attributes(email: email, password: password)
        )

      assert changeset.valid?
      assert get_change(changeset, :email) == email
      assert get_change(changeset, :password) == password
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "change_user_email/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "apply_user_email/3" do
    setup do
      %{user: user_fixture()}
    end

    test "requires email to change", %{user: user} do
      {:error, changeset} = Accounts.apply_user_email(user, valid_user_password(), %{})
      assert %{email: ["did not change"]} = errors_on(changeset)
    end

    test "validates email", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum value for email for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{user: user} do
      %{email: email} = user_fixture()
      password = valid_user_password()

      {:error, changeset} = Accounts.apply_user_email(user, password, %{email: email})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, "invalid", %{email: unique_user_email()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "applies the email without persisting it", %{user: user} do
      email = unique_user_email()
      {:ok, user} = Accounts.apply_user_email(user, valid_user_password(), %{email: email})
      assert user.email == email
      assert Accounts.get_user!(user.id).email != email
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = user_fixture(confirmed: false)
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert Accounts.update_user_email(user, token) == :ok
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      assert changed_user.confirmed_at
      assert changed_user.confirmed_at != user.confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)

      assert %AuditEvent{event: :email_changed, metadata: metadata} =
               Accounts.list_account_audit_events(user) |> List.first()

      assert metadata["old_email"]["email_fingerprint"]
      assert metadata["new_email"]["email_fingerprint"]
      refute inspect(metadata) =~ user.email
      refute inspect(metadata) =~ email
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.update_user_email(user, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(%User{}, %{
          "password" => "new valid password"
        })

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/3" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "short",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 6 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, "invalid", %{password: valid_user_password()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "updates the password", %{user: user} do
      {:ok, user} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")

      assert %AuditEvent{event: :password_changed} =
               Accounts.list_account_audit_events(user) |> List.first()
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, _} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "account audit events" do
    test "records request metadata and sanitizes sensitive metadata" do
      user = user_fixture()

      assert {:ok, audit_event} =
               Accounts.record_account_audit_event(user, :profile_updated, %{
                 ip_address: "127.0.0.1",
                 user_agent: String.duplicate("browser", 120),
                 metadata: %{
                   changed_fields: [:bio, :country],
                   password: "secret",
                   Password: "also-secret",
                   nested: %{token: "secret-token", kept: "safe"}
                 }
               })

      assert audit_event.user_id == user.id
      assert audit_event.event == :profile_updated
      assert audit_event.ip_address == "127.0.0.1"
      assert String.length(audit_event.user_agent) == 512
      assert audit_event.metadata["changed_fields"] == ["bio", "country"]
      assert audit_event.metadata["nested"] == %{"kept" => "safe"}
      refute Map.has_key?(audit_event.metadata, "password")
      refute Map.has_key?(audit_event.metadata, "Password")
      refute inspect(audit_event.metadata) =~ "secret-token"
    end

    test "does not record profile audit events when nothing changes" do
      user = user_fixture()
      audit_event_count = user |> Accounts.list_account_audit_events() |> length()

      assert {:ok, _user} = Accounts.update_user_profile(user, %{})

      assert length(Accounts.list_account_audit_events(user)) == audit_event_count
    end

    test "records failed login attempts without a user or raw email" do
      attempted_email = "Learner+Mistyped@Example.COM"

      assert {:ok, audit_event} =
               Accounts.record_account_audit_event(nil, :login_failed,
                 metadata:
                   attempted_email
                   |> Accounts.audit_email_metadata()
                   |> Map.put("reason", "invalid_credentials")
               )

      assert audit_event.user_id == nil
      assert audit_event.event == :login_failed
      assert audit_event.metadata["reason"] == "invalid_credentials"
      assert audit_event.metadata["email_domain"] == "example.com"
      assert audit_event.metadata["email_fingerprint"]
      refute inspect(audit_event.metadata) =~ attempted_email
      refute inspect(audit_event.metadata) =~ "Learner"
    end

    test "lists audit events for a user newest first with a bounded limit" do
      user = user_fixture()
      other_user = user_fixture()

      {:ok, older} = Accounts.record_account_audit_event(user, :login_succeeded)
      {:ok, newer} = Accounts.record_account_audit_event(user, :logout)
      {:ok, _other} = Accounts.record_account_audit_event(other_user, :login_succeeded)

      assert [^newer] = Accounts.list_account_audit_events(user, limit: 1)
      assert [_event] = Accounts.list_account_audit_events(user, limit: -1)
      assert Enum.any?(Accounts.list_account_audit_events(user), &(&1.id == older.id))
      refute Enum.any?(Accounts.list_account_audit_events(user), &(&1.user_id == other_user.id))
    end

    test "role changes are audited with old and new roles" do
      user = user_fixture()

      assert {:ok, admin} = Accounts.update_user_role(user, :admin)
      assert admin.role == :admin

      assert %AuditEvent{event: :role_changed, metadata: metadata} =
               Accounts.list_account_audit_events(user) |> List.first()

      assert metadata == %{"old_role" => "learner", "new_role" => "admin"}
    end

    test "does not record role audit events when the role does not change" do
      user = user_fixture()
      audit_event_count = user |> Accounts.list_account_audit_events() |> length()

      assert {:ok, unchanged_user} = Accounts.update_user_role(user, :learner)
      assert unchanged_user.role == :learner

      assert length(Accounts.list_account_audit_events(user)) == audit_event_count
    end

    test "confirming an email records an :email_confirmed event" do
      user = user_fixture(confirmed: false)

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      assert {:ok, _confirmed} = Accounts.confirm_user(token)

      assert %AuditEvent{event: :email_confirmed, user_id: user_id} =
               Accounts.list_account_audit_events(user) |> List.first()

      assert user_id == user.id
    end

    test "resetting a password via token records a :password_reset event" do
      user = user_fixture()

      assert {:ok, _updated} =
               Accounts.reset_user_password(user, %{password: "a brand new password"})

      assert %AuditEvent{event: :password_reset, user_id: user_id} =
               Accounts.list_account_audit_events(user) |> List.first()

      assert user_id == user.id
    end

    test "updating a profile records a :profile_updated event listing the changed fields" do
      user = user_fixture()

      assert {:ok, _updated} =
               Accounts.update_user_profile(user, %{
                 "bio" => "Learning GS1.",
                 "country" => "Kenya"
               })

      assert %AuditEvent{event: :profile_updated, metadata: metadata} =
               Accounts.list_account_audit_events(user) |> List.first()

      assert Enum.sort(metadata["changed_fields"]) == ["bio", "country"]
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_user_confirmation_instructions/2" do
    setup do
      %{user: user_fixture(confirmed: false)}
    end

    test "sends token through notification", %{user: user} do
      {:ok, email} =
        Accounts.deliver_user_confirmation_instructions(user, &"[TOKEN]#{&1}[TOKEN]")

      [_, token | _] = String.split(email.text_body, "[TOKEN]")

      assert email.html_body =~ "background-color:#f97316"
      assert email.html_body =~ "logo.png"
      assert email.html_body =~ "We&#39;ll sign you in automatically"
      assert email.text_body =~ "We'll sign you in automatically"

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "confirm"
    end

    test "extract_user_token/1 can still read confirmation tokens from text emails", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "confirm"
    end

    test "does not send a second token inside the resend cooldown", %{user: user} do
      assert {:ok, _email} =
               Accounts.deliver_user_confirmation_instructions(user, &"[TOKEN]#{&1}[TOKEN]")

      assert {:error, :rate_limited} =
               Accounts.deliver_user_confirmation_instructions(user, &"[TOKEN]#{&1}[TOKEN]")

      assert [%UserToken{context: "confirm", user_id: user_id}] =
               Repo.all(UserToken.by_user_and_contexts_query(user, ["confirm"]))

      assert user_id == user.id
    end

    test "allows another confirmation email after the resend cooldown", %{user: user} do
      assert {:ok, _email} =
               Accounts.deliver_user_confirmation_instructions(user, &"[TOKEN]#{&1}[TOKEN]")

      {1, nil} =
        UserToken.by_user_and_contexts_query(user, ["confirm"])
        |> Repo.update_all(
          set: [
            inserted_at:
              DateTime.add(DateTime.utc_now(), -16, :minute) |> DateTime.truncate(:second)
          ]
        )

      assert {:ok, _email} =
               Accounts.deliver_user_confirmation_instructions(user, &"[TOKEN]#{&1}[TOKEN]")

      assert Repo.aggregate(UserToken.by_user_and_contexts_query(user, ["confirm"]), :count) == 2
    end

    test "does not send confirmation instructions to already confirmed users" do
      user = user_fixture()

      assert {:error, :already_confirmed} =
               Accounts.deliver_user_confirmation_instructions(user, &"[TOKEN]#{&1}[TOKEN]")

      refute Repo.get_by(UserToken, user_id: user.id, context: "confirm")
    end
  end

  describe "confirm_user/1" do
    setup do
      user = user_fixture(confirmed: false)

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "confirms the email with a valid token", %{user: user, token: token} do
      assert_email_sent(subject: "Confirmation instructions")
      assert {:ok, confirmed_user} = Accounts.confirm_user(token)
      assert confirmed_user.confirmed_at
      assert confirmed_user.confirmed_at != user.confirmed_at
      assert Repo.get!(User, user.id).confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm with invalid token", %{user: user} do
      assert Accounts.confirm_user("oops") == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.confirm_user(token) == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "reset_password"
    end
  end

  describe "get_user_by_reset_password_token/1" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "returns the user with valid token", %{user: %{id: id}, token: token} do
      assert %User{id: ^id} = Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: id)
    end

    test "does not return the user with invalid token", %{user: user} do
      refute Accounts.get_user_by_reset_password_token("oops")
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not return the user if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "reset_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.reset_user_password(user, %{
          password: "short",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 6 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.reset_user_password(user, %{password: too_long})
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, updated_user} = Accounts.reset_user_password(user, %{password: "new valid password"})
      assert is_nil(updated_user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)
      {:ok, _} = Accounts.reset_user_password(user, %{password: "new valid password"})
      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "change_user_profile/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_profile(%User{})
      assert changeset.required == []
    end

    test "allows all profile fields to be set" do
      changeset =
        Accounts.change_user_profile(%User{}, %{
          "headline" => "Supply Chain Manager",
          "bio" => "Building things.",
          "country" => "Kenya",
          "organization" => "GS1 Kenya",
          "industry" => "Supply Chain & Logistics",
          "occupation" => "Software Engineer",
          "experience_level" => "mid",
          "learning_goal" => "certification",
          "avatar_key" => "https://cdn.example.test/avatars/1/pic.png"
        })

      assert changeset.valid?
      assert get_change(changeset, :headline) == "Supply Chain Manager"
      assert get_change(changeset, :bio) == "Building things."
      assert get_change(changeset, :country) == "Kenya"
      assert get_change(changeset, :organization) == "GS1 Kenya"
      assert get_change(changeset, :industry) == "Supply Chain & Logistics"
      assert get_change(changeset, :occupation) == "Software Engineer"
      assert get_change(changeset, :experience_level) == :mid
      assert get_change(changeset, :learning_goal) == :certification

      assert get_change(changeset, :avatar_key) ==
               "https://cdn.example.test/avatars/1/pic.png"
    end

    test "every field is optional" do
      assert %Ecto.Changeset{valid?: true} = Accounts.change_user_profile(%User{}, %{})
    end

    test "rejects a bio over the length cap" do
      changeset = Accounts.change_user_profile(%User{}, %{"bio" => String.duplicate("a", 501)})
      assert %{bio: ["should be at most 500 character(s)"]} = errors_on(changeset)
    end

    test "accepts a bio at exactly the length cap" do
      changeset = Accounts.change_user_profile(%User{}, %{"bio" => String.duplicate("a", 500)})
      assert changeset.valid?
    end

    test "rejects an occupation over the length cap" do
      changeset =
        Accounts.change_user_profile(%User{}, %{"occupation" => String.duplicate("a", 161)})

      assert %{occupation: ["should be at most 160 character(s)"]} = errors_on(changeset)
    end

    test "rejects a country outside the fixed list" do
      changeset = Accounts.change_user_profile(%User{}, %{"country" => "Atlantis"})
      assert %{country: ["is not a supported country"]} = errors_on(changeset)
    end

    test "accepts a country from the fixed list" do
      changeset = Accounts.change_user_profile(%User{}, %{"country" => "Kenya"})
      assert changeset.valid?
    end

    test "treats an empty-string country as unset rather than invalid" do
      changeset = Accounts.change_user_profile(%User{}, %{"country" => ""})
      assert changeset.valid?
      assert get_change(changeset, :country) == nil
    end

    test "rejects a headline over the length cap" do
      changeset =
        Accounts.change_user_profile(%User{}, %{"headline" => String.duplicate("a", 121)})

      assert %{headline: ["should be at most 120 character(s)"]} = errors_on(changeset)
    end

    test "rejects an organization over the length cap" do
      changeset =
        Accounts.change_user_profile(%User{}, %{"organization" => String.duplicate("a", 161)})

      assert %{organization: ["should be at most 160 character(s)"]} = errors_on(changeset)
    end

    test "rejects an industry outside the fixed list" do
      changeset = Accounts.change_user_profile(%User{}, %{"industry" => "Wizardry"})
      assert %{industry: ["is not a supported industry"]} = errors_on(changeset)
    end

    test "accepts an industry from the fixed list" do
      changeset =
        Accounts.change_user_profile(%User{}, %{"industry" => "Technology & Software"})

      assert changeset.valid?
    end

    test "treats an empty-string industry as unset rather than invalid" do
      changeset = Accounts.change_user_profile(%User{}, %{"industry" => ""})
      assert changeset.valid?
      assert get_change(changeset, :industry) == nil
    end

    test "rejects an experience_level outside the enum" do
      changeset = Accounts.change_user_profile(%User{}, %{"experience_level" => "expert"})
      assert %{experience_level: ["is invalid"]} = errors_on(changeset)
    end

    test "treats an empty-string experience_level as unset rather than invalid" do
      changeset = Accounts.change_user_profile(%User{}, %{"experience_level" => ""})
      assert changeset.valid?
      assert get_change(changeset, :experience_level) == nil
    end

    test "rejects a learning_goal outside the enum" do
      changeset = Accounts.change_user_profile(%User{}, %{"learning_goal" => "fun"})
      assert %{learning_goal: ["is invalid"]} = errors_on(changeset)
    end

    test "treats an empty-string learning_goal as unset rather than invalid" do
      changeset = Accounts.change_user_profile(%User{}, %{"learning_goal" => ""})
      assert changeset.valid?
      assert get_change(changeset, :learning_goal) == nil
    end
  end

  describe "update_user_profile/2" do
    setup do
      %{user: user_fixture()}
    end

    test "persists valid profile fields", %{user: user} do
      {:ok, updated} =
        Accounts.update_user_profile(user, %{
          "headline" => "Supply Chain Manager",
          "bio" => "Learning GS1 standards.",
          "country" => "Uganda",
          "organization" => "GS1 Kenya",
          "industry" => "Supply Chain & Logistics",
          "occupation" => "Supply Chain Analyst",
          "experience_level" => "senior",
          "learning_goal" => "upskilling"
        })

      assert updated.headline == "Supply Chain Manager"
      assert updated.bio == "Learning GS1 standards."
      assert updated.country == "Uganda"
      assert updated.organization == "GS1 Kenya"
      assert updated.industry == "Supply Chain & Logistics"
      assert updated.occupation == "Supply Chain Analyst"
      assert updated.experience_level == :senior
      assert updated.learning_goal == :upskilling
    end

    test "rejects invalid data and leaves the stored record untouched", %{user: user} do
      {:error, changeset} = Accounts.update_user_profile(user, %{"country" => "Nowhereland"})
      assert %{country: ["is not a supported country"]} = errors_on(changeset)
      assert Accounts.get_user!(user.id).country == nil
    end

    test "clears a previously-set field back to nil", %{user: user} do
      {:ok, user} = Accounts.update_user_profile(user, %{"bio" => "Hello."})
      {:ok, user} = Accounts.update_user_profile(user, %{"bio" => nil})
      assert user.bio == nil
    end

    test "never touches email, password, or role", %{user: user} do
      {:ok, updated} =
        Accounts.update_user_profile(user, %{
          "bio" => "Hi",
          "email" => "attacker@example.com",
          "role" => "admin"
        })

      assert updated.email == user.email
      assert updated.role == user.role
    end
  end

  describe "list_users_page/1" do
    test "paginates, newest first" do
      Enum.each(1..3, fn n -> user_fixture(name: "User #{n}") end)

      page = Accounts.list_users_page(page: 1, page_size: 2)

      assert page.total_count == 3
      assert page.total_pages == 2
      assert length(page.entries) == 2
    end

    test "filters by search, same as list_users/1" do
      match = user_fixture(name: "Amina Otieno")
      user_fixture(name: "Brian Kamau")

      page = Accounts.list_users_page(search: "Amina")

      assert [%{id: id}] = page.entries
      assert id == match.id
    end
  end

  describe "Countries" do
    test "list/0 returns all countries with East Africa first" do
      list = Countries.list()
      assert is_list(list)
      assert hd(list) == "Kenya"
      assert "Uganda" in list
      assert "United States" in list
    end

    test "valid?/1 validates supported countries" do
      assert Countries.valid?("Kenya")
      assert Countries.valid?("Tanzania")
      refute Countries.valid?("Atlantis")
      refute Countries.valid?("")
      refute Countries.valid?(nil)
    end

    test "search/1 returns full list for empty or whitespace query" do
      assert Countries.search("") == Countries.list()
      assert Countries.search("   ") == Countries.list()
      assert Countries.search(nil) == Countries.list()
    end

    test "search/1 filters countries case-insensitively" do
      results = Countries.search("ken")
      assert "Kenya" in results

      results = Countries.search("UGANDA")
      assert results == ["Uganda"]

      results = Countries.search("land")
      assert "Finland" in results
      assert "Poland" in results
      assert "Switzerland" in results
      refute "Kenya" in results
    end

    test "search/1 returns empty list when no match" do
      assert Countries.search("NonexistentLandXYZ") == []
    end
  end
end
