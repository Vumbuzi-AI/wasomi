# Workflows

## Browse and Buy a Course

1. A visitor opens `/courses` or `/courses/:slug`.
2. `Wasomi.Catalog` loads published courses and ordered outlines.
3. The visitor registers or logs in through the auth LiveViews.
4. The learner opens `/courses/:slug/checkout`.
5. `Wasomi.Payments.initialize_checkout/4` creates a pending enrollment and pending payment.
6. Paystack returns an authorization URL.
7. Paystack redirects to `/payments/paystack/callback`.
8. `Wasomi.Payments.process_paystack_reference/2` verifies the payment.
9. Successful verification marks the payment successful and activates the enrollment.
10. The learner is redirected into learning access.

## Learn a Course

1. The learner opens `/learn/courses/:slug`.
2. `Wasomi.Enrollments.can_access_course?/2` confirms active enrollment.
3. `Wasomi.Learning.next_lecture/2` and `lecture_unlocked?/3` determine the current lesson and unlock state.
4. The player requests `/media/lectures/:id/playback`.
5. `Wasomi.Media.playback_url/4` authorizes the lecture and returns either a demo HLS URL in development or a provider-backed protected stream URL.
6. Playback events call `Wasomi.Learning.record_progress/3`.
7. Completion at 95 percent or explicit mark-complete saves `LectureProgress`.

## Certificate Issuing

1. `Wasomi.Learning.mark_complete/2` or `record_progress/3` detects a newly completed lecture.
2. Learning checks whether the module or course is now complete.
3. Completion events enqueue `Wasomi.Certificates.Workers.IssueCertificate` jobs.
4. `Wasomi.Certificates.issue/3` re-checks completion, renders a PDF, uploads it through configured storage, and inserts a unique certificate.
5. The learner sees certificates at `/certificates` and downloads through `/certificates/:id/download`.

## Admin Course Management

1. An admin logs in and is redirected to `/admin`.
2. `/admin/courses` lists courses and supports create/edit actions through `AdminLive.Courses`.
3. `/admin/courses/:id` shows course detail, modules, lectures, enrollments, and payment data.
4. Admin content actions call `Wasomi.Catalog` CRUD/reorder functions.
5. `/admin/lectures/:id/video` calls `Wasomi.Media.create_upload/4` and `upload_status/3`; these require an admin user.

## Payment Reconciliation and Webhooks

1. Paystack sends webhook events to `POST /webhooks/paystack`.
2. `PaystackWebhookController` records event data against the matching payment.
3. Oban runs `Wasomi.Payments.Workers.ReconcilePendingPayments` every minute.
4. The worker finds stale pending Paystack payments and verifies them through the payments context.
