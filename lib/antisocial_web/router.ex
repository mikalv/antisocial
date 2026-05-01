defmodule AntisocialWeb.Router do
  use AntisocialWeb, :router

  import AntisocialWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug AntisocialWeb.AliasRedirectPlug
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AntisocialWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public routes
  scope "/", AntisocialWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    post "/login/device", SessionController, :device_login
    get "/invite/:token", InviteController, :show
  end

  # Passkey auth (unauthenticated)
  scope "/passkeys", AntisocialWeb do
    pipe_through :browser

    get "/auth/challenge", PasskeyController, :auth_challenge
    post "/auth", PasskeyController, :auth
  end

  # Passkey management (authenticated)
  scope "/passkeys", AntisocialWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/register/challenge", PasskeyController, :register_challenge
    post "/register", PasskeyController, :register
    delete "/:id", PasskeyController, :delete
  end

  # Redirect root + /hemmelig
  scope "/", AntisocialWeb do
    pipe_through :browser
    get "/", PageController, :index
    get "/hemmelig", PageController, :hemmelig
  end

  # Authenticated routes
  scope "/", AntisocialWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [{AntisocialWeb.UserAuth, :require_authenticated}] do
      live "/onboarding", OnboardingLive, :index
      live "/settings", SettingsLive, :index
      live "/chat/:channel", ChatLive, :show
      live "/bulletin", BulletinLive, :index
    end

    delete "/logout", SessionController, :delete
  end

  # Serve uploaded media (authenticated)
  scope "/media", AntisocialWeb do
    pipe_through [:browser, :require_authenticated_user]
    get "/*path", MediaController, :show
  end

  if Application.compile_env(:antisocial, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: AntisocialWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
