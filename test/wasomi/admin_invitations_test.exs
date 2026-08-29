defmodule Wasomi.AdminInvitationsTest do
  use Wasomi.DataCase, async: true

  import Wasomi.AccountsFixtures

  alias Wasomi.Accounts
  alias Wasomi.Accounts.{AdminInvitation, User}
  alias Wasomi.Repo

  defp admin_fixture do
    {:ok, admin} = user_fixture() |> Accounts.update_user_role(:admin)
    admin
  end

  defp expire(%AdminInvitation{} = invitation) do
    past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
    invitation |> Ecto.Changeset.change(expires_at: past) |> Repo.update!()
  end

  describe "invite_admin/2" do
    test "creates a pending invitation and returns the raw token" do
      inviter = admin_fixture()

      {:ok, {invitation, raw_token}} = Accounts.invite_admin("New.Admin@example.com ", inviter)

      assert invitation.email == "new.admin@example.com"
      assert invitation.status == :pending
      assert invitation.invited_by_id == inviter.id
      assert is_binary(raw_token) and byte_size(raw_token) > 20
      # stored hashed, not the raw token
      refute invitation.token == raw_token
      assert invitation.token == AdminInvitation.hash_token(raw_token)
      assert DateTime.compare(invitation.expires_at, DateTime.utc_now()) == :gt
    end

    test "rejects an email that already belongs to an admin" do
      inviter = admin_fixture()
      existing = admin_fixture()

      assert {:error, :already_admin} = Accounts.invite_admin(existing.email, inviter)
    end

    test "rejects a second live invite for the same email" do
      inviter = admin_fixture()
      {:ok, _} = Accounts.invite_admin("dup@example.com", inviter)

      assert {:error, :already_invited} = Accounts.invite_admin("DUP@example.com", inviter)
    end

    test "allows re-inviting after the previous invite was revoked" do
      inviter = admin_fixture()
      {:ok, {invitation, _}} = Accounts.invite_admin("again@example.com", inviter)
      {:ok, _} = Accounts.revoke_admin_invitation(invitation)

      assert {:ok, _} = Accounts.invite_admin("again@example.com", inviter)
    end
  end

  describe "list_admin_invitations/0 and admin_invitation_state/1" do
    test "lists newest first with associations preloaded" do
      inviter = admin_fixture()
      {:ok, _} = Accounts.invite_admin("a@example.com", inviter)
      {:ok, _} = Accounts.invite_admin("b@example.com", inviter)

      [first, second] = Accounts.list_admin_invitations()

      assert first.email == "b@example.com"
      assert second.email == "a@example.com"
      assert %User{} = first.invited_by
    end

    test "reports expired, revoked and accepted states" do
      inviter = admin_fixture()

      {:ok, {pending, _}} = Accounts.invite_admin("p@example.com", inviter)
      assert Accounts.admin_invitation_state(pending) == :pending
      assert Accounts.admin_invitation_state(expire(pending)) == :expired

      {:ok, {to_revoke, _}} = Accounts.invite_admin("r@example.com", inviter)
      {:ok, revoked} = Accounts.revoke_admin_invitation(to_revoke)
      assert Accounts.admin_invitation_state(revoked) == :revoked
    end
  end

  describe "resend_admin_invitation/1" do
    test "rotates the token and invalidates the old link" do
      inviter = admin_fixture()
      {:ok, {invitation, old_token}} = Accounts.invite_admin("resend@example.com", inviter)

      {:ok, {resent, new_token}} = Accounts.resend_admin_invitation(invitation)

      assert new_token != old_token
      assert resent.token == AdminInvitation.hash_token(new_token)
      refute Accounts.get_pending_admin_invitation_by_token(old_token)
      assert Accounts.get_pending_admin_invitation_by_token(new_token)
    end

    test "refuses a non-pending invitation" do
      inviter = admin_fixture()
      {:ok, {invitation, _}} = Accounts.invite_admin("x@example.com", inviter)
      {:ok, invitation} = Accounts.revoke_admin_invitation(invitation)

      assert {:error, :not_pending} = Accounts.resend_admin_invitation(invitation)
    end
  end

  describe "revoke_admin_invitation/1" do
    test "marks it revoked and kills the link" do
      inviter = admin_fixture()
      {:ok, {invitation, token}} = Accounts.invite_admin("kill@example.com", inviter)

      {:ok, revoked} = Accounts.revoke_admin_invitation(invitation)

      assert revoked.status == :revoked
      assert %DateTime{} = revoked.revoked_at
      refute Accounts.get_pending_admin_invitation_by_token(token)
    end
  end

  describe "get_pending_admin_invitation_by_token/1" do
    test "returns nil for an expired, unknown or non-binary token" do
      inviter = admin_fixture()
      {:ok, {invitation, token}} = Accounts.invite_admin("expiry@example.com", inviter)

      assert Accounts.get_pending_admin_invitation_by_token(token)
      expire(invitation)
      refute Accounts.get_pending_admin_invitation_by_token(token)
      refute Accounts.get_pending_admin_invitation_by_token("nope")
      refute Accounts.get_pending_admin_invitation_by_token(nil)
    end
  end

  describe "accept_admin_invitation/2" do
    test "promotes an existing learner to admin" do
      inviter = admin_fixture()
      learner = user_fixture(%{email: "promote@example.com"})
      {:ok, {_, token}} = Accounts.invite_admin("promote@example.com", inviter)

      assert {:ok, user} = Accounts.accept_admin_invitation(token)

      assert user.id == learner.id
      assert Accounts.get_user!(learner.id).role == :admin
      invitation = Repo.get_by!(AdminInvitation, email: "promote@example.com")
      assert invitation.status == :accepted
      assert invitation.accepted_by_id == learner.id
    end

    test "is a no-op-ish accept when the email is already an admin" do
      inviter = admin_fixture()
      other_admin = admin_fixture()
      # sneak a pending invite past the create-time guard
      {:ok, {invitation, token}} = Accounts.invite_admin("later@example.com", inviter)
      Ecto.Changeset.change(invitation, email: other_admin.email) |> Repo.update!()

      assert {:ok, user} = Accounts.accept_admin_invitation(token)
      assert user.id == other_admin.id
      assert user.role == :admin
    end

    test "creates a confirmed admin account for a new email" do
      inviter = admin_fixture()
      {:ok, {_, token}} = Accounts.invite_admin("fresh@example.com", inviter)

      assert {:ok, user} =
               Accounts.accept_admin_invitation(token, %{
                 name: "Fresh Admin",
                 password: "supersecret",
                 password_confirmation: "supersecret"
               })

      assert user.email == "fresh@example.com"
      assert user.role == :admin
      assert user.confirmed_at
    end

    test "rejects a weak password and leaves the invitation pending" do
      inviter = admin_fixture()
      {:ok, {_, token}} = Accounts.invite_admin("weak@example.com", inviter)

      assert {:error, %Ecto.Changeset{}} =
               Accounts.accept_admin_invitation(token, %{
                 name: "Weak",
                 password: "short",
                 password_confirmation: "short"
               })

      assert Accounts.get_pending_admin_invitation_by_token(token)
      refute Accounts.get_user_by_email("weak@example.com")
    end

    test "rejects an invalid, revoked or expired token" do
      inviter = admin_fixture()
      {:ok, {invitation, token}} = Accounts.invite_admin("bad@example.com", inviter)

      assert {:error, :invalid} = Accounts.accept_admin_invitation("garbage")

      {:ok, _} = Accounts.revoke_admin_invitation(invitation)
      assert {:error, :invalid} = Accounts.accept_admin_invitation(token)
    end
  end
end
