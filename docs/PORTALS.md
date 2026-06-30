# Portals and Routes

Routes are defined in `lib/wasomi_web/router.ex`.

## Public Website

Role: anonymous or signed-in users.

Routes:

- `GET /` - `WasomiWeb.HomeLive`
- `GET /landing` - `WasomiWeb.PageController.home`
- `GET /courses` - `WasomiWeb.CatalogLive.Index`
- `GET /courses/:slug` - `WasomiWeb.CatalogLive.Show`

Purpose: marketing/home page, public course discovery, and published course details.

## Authentication

Role: anonymous users for sign-up/login/reset, current users for confirmation instructions.

Routes:

- `/users/register` - `UserRegistrationLive`
- `/users/log_in` - `UserLoginLive` and `UserSessionController.create`
- `/users/reset_password` and `/users/reset_password/:token`
- `/users/confirm` and `/users/confirm/:token`
- `DELETE /users/log_out` - `UserSessionController.delete`

Purpose: account lifecycle, session creation, confirmation, and password reset.

## Learner Portal

Role: authenticated users, normally `:learner`.

Routes:

- `/dashboard` - `DashboardLive`
- `/courses-taken` - `CoursesTakenLive`
- `/certificates` - `CertificatesLive`
- `/users/settings` - `UserSettingsLive`
- `/courses/:slug/checkout` - `CheckoutLive`
- `/learn/courses/:slug` - `CoursePlayerLive`
- `/media/lectures/:id/playback` - `MediaController.playback`
- `/certificates/:id/download` - `CertificateController.download`
- `/payments/paystack/callback` - `PaystackCallbackController.show`

Purpose: learner account management, paid checkout, course playback, lecture progress, receipts, and certificates.

## Admin Portal

Role: authenticated users with `role: :admin`.

Routes:

- `/admin` - `AdminLive.Dashboard`
- `/admin/courses` - `AdminLive.Courses`
- `/admin/courses/new` - `AdminLive.Courses`
- `/admin/courses/:id/edit` - `AdminLive.Courses`
- `/admin/courses/:id` - `AdminLive.CourseShow`
- `/admin/students` - `AdminLive.Students`
- `/admin/students/:id` - `AdminLive.StudentShow`
- `/admin/payments` - `AdminLive.Payments`
- `/admin/lectures/:id/video` - `AdminLectureVideoLive`

Purpose: operational overview, course content management, learner/payment inspection, and lecture video upload management.

## Webhooks and Developer Tools

Routes:

- `POST /webhooks/paystack` - `PaystackWebhookController.create` through the `:api` pipeline.
- `/dev/dashboard` and `/dev/mailbox` - enabled only when `:dev_routes` is true.

Purpose: payment event ingestion, LiveDashboard metrics, and local Swoosh mailbox preview.

## Generated CRUD Screens

The repo also contains LiveView CRUD modules for courses, modules, lectures, enrollments, lecture progress, payments, and certificates. Not all are currently mounted in `router.ex`; treat unmounted screens as internal/generated scaffolding unless the router exposes them.
