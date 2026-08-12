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
- `/admin/courses/:slug/edit` - `AdminLive.Courses`
- `/admin/courses/:slug` - `AdminLive.CourseShow`
- `/admin/courses/:slug/certificate` - `AdminLive.CourseCertificate`
- `/admin/courses/:slug/preview` - `CoursePlayerLive` (admin "view as learner" mode)
- `/admin/courses/:course_slug/quizzes/:id/edit` - `AdminLive.QuizEdit`
- `/admin/courses/:course_slug/quizzes/:quiz_id` - `AdminLive.QuizShow` (redirect shim to the edit route)
- `/admin/students` - `AdminLive.Students` — search + pagination; a page-level "Export enrollments" CSV link (unfiltered).
- `/admin/students/:id` - `AdminLive.StudentShow`
- `/admin/payments` - `AdminLive.Payments` — two tabs (`?tab=payments`/`?tab=revenue`), each with its own search/status-filter/sort/pagination; a page-level "Export payments" CSV link (unfiltered).
- `/admin/analytics` - `AdminLive.Analytics` — filterable (course/date-range) by a shared form; Overview tab (conversion funnel + course leaderboard) and Revenue tab (monthly revenue + revenue-by-course charts); a filtered "Export quiz results" CSV link (the one export type with no better single-page home).
- `/admin/lectures/:id/video` - `AdminLectureVideoLive`
- `/admin/exports/:type` - `Admin.ExportController` (controller, not a LiveView) — streams a CSV for `type` in `enrollments`/`payments`/`quiz_results`. Only invoked with `course_id`/`from`/`to` query params from the Analytics page's filter form (quiz results); the Students/Payments page-level export links call it unfiltered.

Purpose: operational overview, course content management, learner/payment inspection, lecture video upload management, and CSV data export.

## Webhooks and Developer Tools

Routes:

- `POST /webhooks/paystack` - `PaystackWebhookController.create` through the `:api` pipeline.
- `/dev/dashboard` and `/dev/mailbox` - enabled only when `:dev_routes` is true.

Purpose: payment event ingestion, LiveDashboard metrics, and local Swoosh mailbox preview.

## Generated CRUD Screens

The repo also contains LiveView CRUD modules for courses, modules, lectures, enrollments, lecture progress, payments, and certificates. Not all are currently mounted in `router.ex`; treat unmounted screens as internal/generated scaffolding unless the router exposes them.
