## Assessment & Quiz Data Architecture
Generate Ecto migrations and schemas for Quiz, Question, QuestionOption, and QuizSubmission. Implement the Wasomi.Assessments context with CRUD functions, quiz score calculation logic, and database constraints for unique positioning and mandatory correct options.

Acceptance Criteria:
- Database migration creates quizzes, questions, question_options, and quiz_submissions tables with proper foreign keys.
- Deleting a quiz cascades to delete associated questions and options.
- submit_quiz/2 context function calculates student percentage score and evaluates passing status.
- Prevents saving questions with zero designated correct options.
- Unit tests verify passing, failing, and partial submission evaluations.


## PDF Document Ingestion & AI Question Generation Engine
Implement pdf2text text extraction and an AI generation service calling LLM APIs with structured JSON output constraints. Wrap execution in an Oban background job GenerateQuizFromPDFWorker so large PDFs do not block HTTP requests. Broadcast real-time PubSub events when question draft generation completes.

Acceptance Criteria:
- Admin can upload a PDF document (up to 25MB) for AI processing.
- Text is extracted and sent to LLM API requesting formatted multiple-choice questions.
- Draft questions and options are saved directly into the target quiz with draft status.
- System handles API timeouts and malformed responses with automatic Oban retries.
- Admin receives a real-time PubSub notification when draft questions are ready for review.

Dependencies:
- Task: Assessment & Quiz Data Architecture


## Course Lifecycle State Machine & Pre-Publish Guard
Add status states to Course schema (draft -> in_review -> published). Implement Wasomi.Catalog.PublishGuard to check that courses have at least 1 module, all lectures have content/video, price is set, and thumbnails are attached before allowing publication.

Acceptance Criteria:
- Admin sees current course state (Draft, In Review, Published) on the course edit page.
- Clicking Publish Course executes automated validation checks.
- If checks fail, status remains Draft and a structured checklist of missing items is displayed in a warning banner.
- Successfully publishing makes the course visible in the public course catalog.
- Course price block displays cleanly without stray orange side borders or broken styling.



## Admin "View as Learner" Interactive Preview Mode
Add a Preview Course button to AdminLive.CourseShow mounting WasomiWeb.CoursePlayerLive with an admin socket override flag. Bypass enrollment pay-gate checks while ensuring test progress and quiz answers taken in preview mode are not saved to analytics.

Acceptance Criteria:
- Admin can click Preview Course and navigate through all modules, lectures, and quizzes.
- Enrollment pay-gate checks are bypassed for authenticated admins.
- Prominent top banner indicates Admin Preview Mode — Progress and quiz scores will not be recorded.
- Preview mode works accurately on both desktop and mobile viewports.

Dependencies:
- Task: Course Lifecycle State Machine & Pre-Publish Guard


