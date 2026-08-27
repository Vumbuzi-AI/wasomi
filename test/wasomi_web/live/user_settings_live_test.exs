defmodule WasomiWeb.UserSettingsLiveTest do
  use WasomiWeb.ConnCase, async: true

  alias Wasomi.Accounts
  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Change Email"
      assert html =~ "Change Password"
    end

    test "switches between settings submenu panels", %{conn: conn} do
      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ ~s(id="settings-profile-panel" class="block")
      assert html =~ ~s(id="settings-security-panel" class="hidden")

      html =
        lv
        |> element("a[href='/users/settings?section=security']", "Account & Security")
        |> render_click()

      assert html =~ ~s(id="settings-profile-panel" class="hidden")
      assert html =~ ~s(id="settings-security-panel" class="block")

      html =
        lv
        |> element("a[href='/users/settings?section=profile']", "Profile")
        |> render_click()

      assert html =~ ~s(id="settings-profile-panel" class="block")
      assert html =~ ~s(id="settings-security-panel" class="hidden")

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings?section=unknown")

      assert html =~ ~s(id="settings-profile-panel" class="block")
    end

    test "opens a settings submenu directly from the URL", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings?section=security")

      assert html =~ ~s(id="settings-profile-panel" class="hidden")
      assert html =~ ~s(id="settings-security-panel" class="block")
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log_in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      password = valid_user_password()
      user = user_fixture(%{password: password})
      %{conn: log_in_user(conn, user), user: user, password: password}
    end

    test "updates the user email", %{conn: conn, password: password, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "current_password" => password,
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Accounts.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "current_password" => "invalid",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "current_password" => "invalid",
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
      assert result =~ "is not valid"
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      password = valid_user_password()
      user = user_fixture(%{password: password})
      %{conn: log_in_user(conn, user), user: user, password: password}
    end

    test "updates the user password", %{conn: conn, user: user, password: password} do
      new_password = valid_user_password()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      form =
        form(lv, "#password_form", %{
          "current_password" => password,
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/users/settings"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "current_password" => "invalid",
          "user" => %{
            "password" => "short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Change Password"
      assert result =~ "should be at least 6 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#password_form", %{
          "current_password" => "invalid",
          "user" => %{
            "password" => "short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Change Password"
      assert result =~ "should be at least 6 character(s)"
      assert result =~ "does not match password"
      assert result =~ "is not valid"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm_email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/users/settings/confirm_email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm_email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/users/settings/confirm_email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log_in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end

  describe "update profile form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders the profile section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/settings")

      assert html =~ "Save Profile"
      assert html =~ "other learner ever sees this"
    end

    test "updates every profile field", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      # `country` is a JS-driven combobox (a hidden input, not a native
      # <select>), so it's submitted as a direct event dispatch — exactly
      # what the picker's own JS does on selection — rather than through
      # `form/3`, which only accepts values a real <select>/<option> or
      # unedited hidden input could already produce.
      render_submit(view, "save_profile", %{
        "user" => %{
          "headline" => "Warehouse Ops Lead",
          "bio" => "GS1 Kenya learner.",
          "country" => "Kenya",
          "organization" => "GS1 Kenya",
          "industry" => "Supply Chain & Logistics",
          "occupation" => "Warehouse Manager",
          "experience_level" => "mid",
          "learning_goal" => "upskilling"
        }
      })

      updated = Accounts.get_user!(user.id)
      assert updated.headline == "Warehouse Ops Lead"
      assert updated.bio == "GS1 Kenya learner."
      assert updated.country == "Kenya"
      assert updated.organization == "GS1 Kenya"
      assert updated.industry == "Supply Chain & Logistics"
      assert updated.occupation == "Warehouse Manager"
      assert updated.experience_level == :mid
      assert updated.learning_goal == :upskilling
    end

    test "leaves every field optional", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view
      |> form("#profile_form", %{
        "user" => %{
          "headline" => "",
          "bio" => "",
          "country" => "",
          "organization" => "",
          "industry" => "",
          "occupation" => "",
          "experience_level" => "",
          "learning_goal" => ""
        }
      })
      |> render_submit()

      updated = Accounts.get_user!(user.id)
      assert updated.headline in [nil, ""]
      assert updated.bio in [nil, ""]
      assert updated.country == nil
      assert updated.organization in [nil, ""]
      assert updated.industry == nil
      assert updated.occupation in [nil, ""]
      assert updated.experience_level == nil
      assert updated.learning_goal == nil
    end

    test "renders a validation error on phx-change for a bio over the length cap", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      html =
        view
        |> element("#profile_form")
        |> render_change(%{"user" => %{"bio" => String.duplicate("a", 501)}})

      assert html =~ "should be at most 500 character(s)"
    end

    test "rejects a country outside the fixed list on submit", %{conn: conn} do
      # The country picker is a JS-driven combobox, not a native <select>, so
      # there's no DOM-level option list to bypass — going straight to the
      # event proves the server-side guard holds regardless.
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      html = render_submit(view, "save_profile", %{"user" => %{"country" => "Atlantis"}})

      assert html =~ "is not a supported country"
    end

    test "does not let a learner see or edit another learner's saved profile", %{conn: conn} do
      other = user_fixture()

      {:ok, _} =
        Accounts.update_user_profile(other, %{
          "bio" => "This belongs to someone else.",
          "country" => "Uganda",
          "occupation" => "Should not appear"
        })

      {:ok, _lv, html} = live(conn, ~p"/users/settings")

      refute html =~ "This belongs to someone else."
      refute html =~ "Should not appear"
    end

    test "rejects an avatar over the 2 MB limit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      avatar =
        file_input(view, "#profile_form", :avatar, [
          %{name: "huge.png", content: String.duplicate("a", 2_000_001), type: "image/png"}
        ])

      assert {:error, [[_ref, %{reason: :too_large}]]} = render_upload(avatar, "huge.png")
      assert render(view) =~ "larger than the 2 MB limit"
    end

    test "uploading an avatar shows a preview immediately, before saving", %{
      conn: conn,
      user: user
    } do
      previous_provider = Application.get_env(:wasomi, :storage_provider)
      on_exit(fn -> Application.put_env(:wasomi, :storage_provider, previous_provider) end)
      Application.put_env(:wasomi, :storage_provider, __MODULE__.AvatarStorageMock)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      avatar =
        file_input(view, "#profile_form", :avatar, [
          %{name: "avatar.png", content: "fake-png-bytes", type: "image/png"}
        ])

      html = render_upload(avatar, "avatar.png")
      assert html =~ "https://cdn.example.test/avatars/#{user.id}/avatar.png"
      assert html =~ ~s(alt="Avatar preview")
      refute Accounts.get_user!(user.id).avatar_key
    end

    test "an uploaded avatar persists once the form is saved", %{conn: conn, user: user} do
      previous_provider = Application.get_env(:wasomi, :storage_provider)
      on_exit(fn -> Application.put_env(:wasomi, :storage_provider, previous_provider) end)
      Application.put_env(:wasomi, :storage_provider, __MODULE__.AvatarStorageMock)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      avatar =
        file_input(view, "#profile_form", :avatar, [
          %{name: "avatar.png", content: "fake-png-bytes", type: "image/png"}
        ])

      render_upload(avatar, "avatar.png")

      view
      |> form("#profile_form", %{"user" => %{"bio" => "Hi"}})
      |> render_submit()

      assert Accounts.get_user!(user.id).avatar_key ==
               "https://cdn.example.test/avatars/#{user.id}/avatar.png"
    end

    test "removing a saved avatar clears it, but only once the form is saved", %{
      conn: _conn,
      user: user
    } do
      {:ok, user} =
        Accounts.update_user_profile(user, %{"avatar_key" => "https://cdn.example.test/old.png"})

      conn = log_in_user(build_conn(), user)
      {:ok, view, html} = live(conn, ~p"/users/settings")
      assert html =~ "https://cdn.example.test/old.png"

      html =
        view
        |> element("button[phx-click='remove-avatar']")
        |> render_click()

      refute html =~ "https://cdn.example.test/old.png"
      assert Accounts.get_user!(user.id).avatar_key == "https://cdn.example.test/old.png"

      view
      |> form("#profile_form", %{"user" => %{"bio" => "Hi"}})
      |> render_submit()

      assert Accounts.get_user!(user.id).avatar_key == nil
    end

    test "canceling a pending avatar upload drops it", %{conn: conn} do
      previous_provider = Application.get_env(:wasomi, :storage_provider)
      on_exit(fn -> Application.put_env(:wasomi, :storage_provider, previous_provider) end)
      Application.put_env(:wasomi, :storage_provider, __MODULE__.AvatarStorageMock)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      avatar =
        file_input(view, "#profile_form", :avatar, [
          %{name: "avatar.png", content: "fake-png-bytes", type: "image/png"}
        ])

      render_upload(avatar, "avatar.png")

      html =
        view
        |> element("button[phx-click='cancel-avatar-upload']")
        |> render_click()

      refute html =~ "cdn.example.test"
    end

    test "an avatar upload with no public URL configured flashes an error instead of silently dropping it",
         %{conn: conn, user: user} do
      previous_provider = Application.get_env(:wasomi, :storage_provider)
      on_exit(fn -> Application.put_env(:wasomi, :storage_provider, previous_provider) end)
      Application.put_env(:wasomi, :storage_provider, __MODULE__.NoPublicUrlAvatarStorageMock)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      avatar =
        file_input(view, "#profile_form", :avatar, [
          %{name: "avatar.png", content: "fake-png-bytes", type: "image/png"}
        ])

      render_upload(avatar, "avatar.png")

      html =
        view
        |> form("#profile_form", %{"user" => %{"bio" => "Hi"}})
        |> render_submit()

      assert html =~ "R2_PUBLIC_URL"
      refute Accounts.get_user!(user.id).avatar_key
    end

    test "renders country as a searchable combobox with East Africa options first", %{
      conn: conn
    } do
      {:ok, view, html} = live(conn, ~p"/users/settings")

      assert has_element?(view, "[phx-hook='SearchableSelect']")
      assert has_element?(view, "input[type='hidden'][name='user[country]']")
      assert html =~ "Select a country"
      assert html =~ "East Africa"
      assert html =~ "Kenya"
      assert html =~ "Uganda"
      assert html =~ "Tanzania"

      east_africa_index = :binary.match(html, "East Africa") |> elem(0)
      kenya_index = :binary.match(html, "Kenya") |> elem(0)
      assert east_africa_index < kenya_index
    end

    test "the trigger shows the currently saved country", %{conn: _conn} do
      {:ok, user} = Accounts.update_user_profile(user_fixture(), %{"country" => "Uganda"})
      conn = log_in_user(build_conn(), user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      assert has_element?(view, "[data-role='trigger-label']", "Uganda")
    end

    test "selects a country via the searchable combobox", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_submit(view, "save_profile", %{"user" => %{"country" => "Tanzania"}})

      assert Accounts.get_user!(user.id).country == "Tanzania"
    end

    test "clears selected country by submitting empty country value", %{user: user} do
      {:ok, user} = Accounts.update_user_profile(user, %{"country" => "Kenya"})
      conn = log_in_user(build_conn(), user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_submit(view, "save_profile", %{"user" => %{"country" => ""}})

      assert Accounts.get_user!(user.id).country == nil
    end
  end

  defmodule AvatarStorageMock do
    def presign_upload(user, _attrs) do
      {:ok,
       %{
         url: "https://r2.example.test/presigned-url",
         key: "avatars/#{user.id}/avatar.png",
         public_url: "https://cdn.example.test/avatars/#{user.id}/avatar.png",
         content_type: "image/png"
       }}
    end
  end

  defmodule NoPublicUrlAvatarStorageMock do
    def presign_upload(user, _attrs) do
      {:ok,
       %{
         url: "https://r2.example.test/presigned-url",
         key: "avatars/#{user.id}/avatar.png",
         public_url: nil,
         content_type: "image/png"
       }}
    end
  end
end
