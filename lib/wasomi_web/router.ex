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

    live_session :require_authenticated_user,
      on_mount: [{WasomiWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
      live "/dashboard", DashboardLive, :index
      live "/courses-taken", CoursesTakenLive, :index
      live "/certificates", CertificatesLive, :index
      live "/courses/:slug/checkout", CheckoutLive, :show
      live "/learn/courses/:slug", CoursePlayerLive, :show
    end

    get "/media/lectures/:id/playback", MediaController, :playback
    get "/certificates/:id/download", CertificateController, :download
    get "/payments/paystack/callback", PaystackCallbackController, :show
  end

  scope "/admin", WasomiWeb do
    pipe_through [:browser, :require_authenticated_user, :require_admin]

    live_session :require_admin,
      on_mount: [{WasomiWeb.UserAuth, :ensure_admin}] do
      live "/", AdminLive.Dashboard, :index

      live "/courses", AdminLive.Courses, :index
      live "/courses/new", AdminLive.Courses, :new
      live "/courses/:id/edit", AdminLive.Courses, :edit
      live "/courses/:id", AdminLive.CourseShow, :show

      live "/students", AdminLive.Students, :index
      live "/students/:id", AdminLive.StudentShow, :show

      live "/payments", AdminLive.Payments, :index

      live "/lectures/:id/video", AdminLectureVideoLive, :edit
    end
  end

  scope "/", WasomiWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{WasomiWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
end
