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

Confirmed email is now part of the application access gate. A user can hold a
valid session token and still be redirected to `/users/confirm` until
`users.confirmed_at` is set. This keeps registration/login simple while
preventing unconfirmed accounts from reaching learner, admin, media,
download, checkout, or payment-callback surfaces.

The confirmation instructions page has two states. Signed-in unconfirmed
users see the email already on their account and can resend without typing it
again. Anonymous visitors still get an email field so they can request a
fresh link from outside a session. If a learner signed up with the wrong
email, a "Back to sign up" link returns them to the registration form,
prefilled with what they entered, so they can correct it.

The confirmation link itself is a two-step GET/POST: visiting it (`GET
/users/confirm/:token`) only looks the token up and shows a confirm button —
it never mutates state, so an email security scanner pre-fetching the link
can't burn the one-time token before the recipient clicks it. Confirming and
logging in only happen on the `POST` from that button, a real user gesture.

## Router Pipelines

- `:browser` accepts `html` and `json`, fetches session/flash, applies CSRF and secure headers, and assigns `current_user`.
- `:api` accepts JSON and is used for Paystack webhooks.
- `:require_authenticated_user` redirects anonymous users to `/users/log_in`
  and unconfirmed users to `/users/confirm`.
- `:require_admin` allows only confirmed `role: :admin` users.

## LiveView Hooks

`WasomiWeb.UserAuth.on_mount/4` supports:

- `:mount_current_user` - assign user or nil.
- `:ensure_authenticated` - require a confirmed user; anonymous users redirect
  to login, unconfirmed users redirect to `/users/confirm`.
- `:redirect_if_user_is_authenticated` - keep logged-in users out of auth screens.
- `:ensure_admin` - require a confirmed admin, else redirect with an error flash.

## Role to Portal Mapping

- Anonymous users can browse `/`, `/landing`, `/courses`, and `/courses/:slug`.
- Unconfirmed signed-in users can reach the confirmation screens but not the
  learner or admin portals.
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
