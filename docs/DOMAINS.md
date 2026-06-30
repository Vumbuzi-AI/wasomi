# Domains

## Accounts

Context: `Wasomi.Accounts`

Schemas:

- `Wasomi.Accounts.User` backed by `users`
- `Wasomi.Accounts.UserToken` backed by `users_tokens`

Responsibility: registration, login, session tokens, email confirmation, password reset, settings, and admin role changes.

Key functions include `register_user/1`, `get_user_by_email_and_password/2`, `generate_user_session_token/1`, `confirm_user/1`, `update_user_password/3`, `list_users/1`, `count_users/1`, and `update_user_role/2`.

Roles are `:learner` and `:admin`. Public registration deliberately ignores `role`; promotion happens through `update_user_role/2`.

## Catalog

Context: `Wasomi.Catalog`

Schemas:

- `Wasomi.Catalog.Course` backed by `courses`
- `Wasomi.Catalog.CourseModule` backed by `modules`
- `Wasomi.Catalog.Lecture` backed by `lectures`

Responsibility: course content, public catalog ordering, outlines, prices, lecture metadata, and admin CRUD/reordering.

Key functions include `list_published_courses/0`, `get_published_course_by_slug!/1`, `get_course_with_outline!/1`, `format_price/1`, `create_course/1`, `update_course/2`, `reorder_course_modules/2`, `create_course_module/1`, `reorder_module_lectures/2`, and lecture CRUD functions.

Catalog connects to enrollments for access control, payments for checkout amounts, learning for progress, and certificates for completion scopes.

## Enrollments

Context: `Wasomi.Enrollments`

Schema:

- `Wasomi.Enrollments.Enrollment` backed by `enrollments`

Responsibility: course access state. Enrollments are either `:pending` checkout attempts or `:active` learner access records.

Key functions include `create_pending_enrollment/2`, `activate_enrollment/1`, `list_active_for_user/1`, `active_enrollment/2`, `can_access_course?/2`, `can_access_lecture?/2`, and admin count/list functions.

Payments activate enrollments after verified successful payment. Learning and media use enrollments to authorize lecture access.

## Payments

Context: `Wasomi.Payments`

Schema:

- `Wasomi.Payments.Payment` backed by `payments`

Responsibility: checkout creation, Paystack initialization and verification, webhook payload storage, revenue summaries, receipts, and stale pending reconciliation.

Key functions include `initialize_checkout/4`, `create_pending_checkout/3`, `process_paystack_reference/2`, `record_webhook_event/2`, `list_receipts_for_user/1`, `list_recent_payments/1`, `total_revenue_minor/0`, and `list_stale_pending_payments/1`.

Payments create pending enrollments and activate them inside a transaction after Paystack verification succeeds.

## Learning

Context: `Wasomi.Learning`

Schema:

- `Wasomi.Learning.LectureProgress` backed by `lecture_progress`

Responsibility: playback progress, lecture completion, sequential unlocks, module/course completion detection, and completion events.

Key functions include `record_progress/3`, `mark_complete/2`, `progress_for_course/2`, `course_progress/2`, `lecture_unlocked?/3`, `next_lecture/2`, `module_complete?/2`, and `course_complete?/2`.

Learning depends on enrollments for access and emits events that enqueue certificate issuance.

## Certificates

Context: `Wasomi.Certificates`

Schema:

- `Wasomi.Certificates.Certificate` backed by `certificates`

Responsibility: idempotent module and course certificate issuance, serial numbers, object keys, signed download URLs, and user notifications.

Key functions include `enqueue_for_completion_events/2`, `issue/3`, `download_url/3`, `list_for_user/1`, `list_for_user_course/2`, and CRUD helpers.

Certificates use `Wasomi.Certificates.Workers.IssueCertificate`, a renderer module from `:certificate_renderer`, and a storage module from `:certificate_storage`.

## Media

Context: `Wasomi.Media`

Responsibility: protected video playback URLs, admin upload creation/status, and adapter boundaries for Mux or local demo streaming.

Key functions include `playback_token/4`, `playback_url/4`, `create_upload/4`, `upload_status/3`, and `configured_adapter/0`.

Only admins can create uploads or check upload status. Learner playback requires active enrollment.

## Notifications

Context: `Wasomi.Notifications`

Responsibility: transactional notification entry point. Current synchronous delivery sends welcome email through `Wasomi.Accounts.UserNotifier`; workers exist for certificate-issued notifications.

## Paystack

Adapter: `Wasomi.Paystack`

Responsibility: Paystack HTTP calls for transaction initialization and verification. It implements `Wasomi.Payments.Provider`.
