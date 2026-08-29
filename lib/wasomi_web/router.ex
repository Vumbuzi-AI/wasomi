defmodule WasomiWeb.Router do
  use WasomiWeb, :router

  import WasomiWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WasomiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug WasomiWeb.Plugs.ReferralCapture
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/webhooks", WasomiWeb do
    pipe_through :api
    post "/paystack", PaystackWebhookController, :create
  end

  scope "/", WasomiWeb do
    pipe_through :browser

    live "/", HomeLive
    get "/landing", PageController, :home
    get "/sitemap.xml", SitemapController, :index
    get "/join", ReferralController, :join

    # Public page, but auth-aware: signed-in learners get the app sidebar
    # shell; anonymous visitors get the standalone marketing chrome.
    live_session :learner_public_profile,
      on_mount: [{WasomiWeb.UserAuth, :mount_current_user}] do
      live "/learners/:slug", LearnerProfileLive, :show
    end

    # GS1 Digital Link shape (AI(253) = GDTI) — see TODO.md's GDTI
    # decisions. No auth, no on_mount: the result is the same for every
    # visitor regardless of whether they're signed in.
    live "/certificates/253/:gdti", CertificateVerificationLive, :show

    live_session :public_catalog,
      on_mount: [{WasomiWeb.UserAuth, :mount_current_user}] do
      live "/courses", CatalogLive.Index, :index
      live "/courses/:slug", CatalogLive.Show, :show
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", WasomiWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:wasomi, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: WasomiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", WasomiWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{WasomiWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", WasomiWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :onboarding,
      on_mount: [{WasomiWeb.UserAuth, :ensure_authenticated}] do
      live "/welcome", WelcomeLive, :index
    end

    live_session :require_authenticated_user,
      on_mount: [
        {WasomiWeb.UserAuth, :ensure_authenticated},
        {WasomiWeb.UserAuth, :redirect_admins_from_learner_area},
        {WasomiWeb.UserAuth, :ensure_onboarded}
      ] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
      live "/dashboard", DashboardLive, :index
      live "/discussions", DiscussionsLive, :index
      live "/notifications", NotificationsLive, :index
      live "/catalog", CatalogLive.Portal, :index
      live "/courses-taken", CoursesTakenLive, :index
      live "/certificates", CertificatesLive, :index
      live "/refer", ReferLive, :index
      live "/receipts", ReceiptsLive, :index
      live "/courses/:slug/checkout", CheckoutLive, :show
      live "/learn/courses/:slug", CoursePlayerLive, :show
      live "/learn/study", StudyHubLive, :index
    end

    get "/media/lectures/:id/playback", MediaController, :playback
    get "/learn/resources/:id/download", ResourceController, :download
    get "/certificates/:id/download", CertificateController, :download
    get "/certificates/:id/preview", CertificateController, :preview
    get "/receipts/:id/download", ReceiptController, :download
    get "/payments/paystack/callback", PaystackCallbackController, :show
  end

  scope "/admin", WasomiWeb do
    pipe_through [:browser, :require_authenticated_user, :require_admin]

    get "/exports/:type", Admin.ExportController, :show

    live_session :require_admin,
      on_mount: [{WasomiWeb.UserAuth, :ensure_admin}] do
      live "/", AdminLive.Dashboard, :index

      live "/settings", AdminLive.Settings, :edit
      live "/settings/confirm_email/:token", AdminLive.Settings, :confirm_email

      live "/courses", AdminLive.Courses, :index
      live "/courses/new", AdminLive.Courses, :new
      live "/courses/:slug/edit", AdminLive.Courses, :edit
      live "/courses/:slug", AdminLive.CourseShow, :show
      live "/courses/:slug/certificate", AdminLive.CourseCertificate, :edit

      live "/discussions", AdminLive.Discussions, :index

      live "/students", AdminLive.Students, :index
      live "/students/:id", AdminLive.StudentShow, :show

      live "/invitations", AdminLive.Invitations, :index

      live "/mentors", AdminLive.Mentors, :index
      live "/mentors/new", AdminLive.Mentors, :new
      live "/mentors/:id/edit", AdminLive.Mentors, :edit

      live "/payments", AdminLive.Payments, :index

      live "/analytics", AdminLive.Analytics, :index

      live "/landing-images", AdminLive.LandingImages, :index

      live "/courses/:course_slug/quizzes/:id/edit", AdminLive.QuizEdit, :edit
      live "/courses/:course_slug/quizzes/:quiz_id", AdminLive.QuizShow, :show
      live "/courses/:course_slug/lectures/:lecture_id/quiz", AdminLive.LectureQuizEdit, :edit

      live "/courses/:slug/preview", CoursePlayerLive, :preview
    end
  end

  scope "/", WasomiWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete
    get "/users/confirm/:token", UserConfirmationController, :show
    post "/users/confirm/:token", UserConfirmationController, :confirm
    get "/users/log_in/:token", MagicLinkSessionController, :show
    post "/users/log_in/:token", MagicLinkSessionController, :create

    live_session :current_user,
      on_mount: [{WasomiWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm", UserConfirmationInstructionsLive, :new
      live "/admin-invitations/accept/:token", AdminInvitationAcceptLive, :show
    end
  end
end
