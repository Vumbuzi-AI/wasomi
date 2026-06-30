# Authentication and Authorization

Authentication lives in `Wasomi.Accounts` and `WasomiWeb.UserAuth`.

## User Model

`users` has `name`, `email`, optional `phone`, `hashed_password`, `confirmed_at`, and `role`.

Allowed roles:

- `:learner` - default public sign-up role.
- `:admin` - can access `/admin` and admin media upload actions.

`Wasomi.Accounts.User.registration_changeset/3` casts only `name`, `email`, and `password`, so public registration cannot self-assign an admin role. Admin promotion uses `Wasomi.Accounts.update_user_role/2`.

## Sessions

Login calls `Wasomi.Accounts.generate_user_session_token/1` and stores the token in the session. A signed remember-me cookie can also restore the token. Logout deletes the session token and broadcasts a LiveView disconnect.

## Router Pipelines

- `:browser` accepts `html` and `json`, fetches session/flash, applies CSRF and secure headers, and assigns `current_user`.
- `:api` accepts JSON and is used for Paystack webhooks.
- `:require_authenticated_user` redirects anonymous users to `/users/log_in`.
- `:require_admin` allows only `role: :admin`.

## LiveView Hooks

`WasomiWeb.UserAuth.on_mount/4` supports:

- `:mount_current_user` - assign user or nil.
- `:ensure_authenticated` - require a user, else redirect to login.
- `:redirect_if_user_is_authenticated` - keep logged-in users out of auth screens.
- `:ensure_admin` - require an admin, else redirect with an error flash.

## Role to Portal Mapping

- Anonymous users can browse `/`, `/landing`, `/courses`, and `/courses/:slug`.
- Learners sign in to `/dashboard`, checkout, learning, certificates, and settings.
- Admins sign in to `/admin`; `signed_in_path/1` routes admins there after login.

## Secondary Authorization

There is no PIN or secondary-auth mechanism in this codebase. Course playback authorization is domain-based: `Wasomi.Media` calls `Wasomi.Enrollments.authorize_lecture/2`, which requires an active enrollment.

## Adding a Role

1. Add the role atom to `Wasomi.Accounts.User` `Ecto.Enum`.
2. Update `users_role_must_be_valid` with a migration.
3. Add route pipelines or LiveView hooks in `WasomiWeb.UserAuth`.
4. Mount the new portal scope in `WasomiWeb.Router`.
5. Add tests for plugs, hooks, redirects, and any role-specific context functions.
