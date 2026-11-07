# ルーターは各画面と連携エンドポイントを束ねるため依存数が増える。個別に許可する。
# credo:disable-for-this-file Credo.Check.Refactor.ModuleDependencies
defmodule HelpdeskCommanderWeb.Router do
  use HelpdeskCommanderWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HelpdeskCommanderWeb.Layouts, :root}
    plug :protect_from_forgery
    # CSP: 外部スクリプト・object 埋め込みを禁止し、LiveView の ws/wss と
    # インラインスタイルだけを許可する。
    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self' ws: wss:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'"
    }
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", HelpdeskCommanderWeb do
    pipe_through :browser

    get "/sign-in", AuthController, :new
    get "/auth/sso/start/:company_code", SSOController, :new
    get "/auth/sso/callback", SSOController, :callback
    post "/sign-in", AuthController, :create
    get "/sign-up", AuthController, :new_registration
    post "/sign-up", AuthController, :create_registration
    delete "/sign-out", AuthController, :delete
    get "/reports/analytics.csv", ReportController, :analytics_csv
    get "/attachments/:id", AttachmentController, :download

    live_session :user_required,
      on_mount: {HelpdeskCommanderWeb.LiveUserAuth, :live_user_required} do
      live "/", DashboardLive, :home
      live "/tickets", TicketLive.Index, :index
      live "/tickets/new", TicketLive.New, :new
      live "/tickets/:public_id", TicketLive.Show, :show
      live "/inquiries/new", InquiryLive.New, :new
      live "/notifications", NotificationLive.Index, :index
    end

    live_session :internal_required,
      on_mount: {HelpdeskCommanderWeb.LiveUserAuth, :internal_required} do
      live "/tasks", TaskLive.Index, :index
      live "/tasks/new", TaskLive.New, :new
      live "/tasks/:public_id", TaskLive.Show, :show
      live "/products", ProductLive.Index, :index
      live "/products/:id", ProductLive.Show, :show
      live "/relations", RelationGraphLive.Index, :index
      live "/settings/sla", SlaLive.Index, :index
    end

    live_session :admin_required,
      on_mount: {HelpdeskCommanderWeb.LiveUserAuth, :admin_required} do
      live "/admin/pending-users", AdminUserLive.Pending, :index
      live "/admin/attachment-rules", AdminAttachmentRuleLive, :index
    end
  end

  scope "/api/v1", HelpdeskCommanderWeb.Api.V1 do
    pipe_through :api

    post "/sign-in", SessionController, :create
    get "/openapi.json", SpecController, :show
  end

  scope "/api/v1", HelpdeskCommanderWeb.Api.V1 do
    pipe_through :api
    pipe_through HelpdeskCommanderWeb.Plugs.ApiAuth

    get "/me", SessionController, :me
    get "/products", ProductController, :index
    get "/tickets", TicketController, :index
    post "/tickets", TicketController, :create
    get "/tickets/:public_id", TicketController, :show
    patch "/tickets/:public_id", TicketController, :update
    put "/tickets/:public_id", TicketController, :update
    put "/tickets/:public_id/status", TicketController, :set_status
    get "/tickets/:public_id/messages", TicketController, :messages
  end

  scope "/integrations", HelpdeskCommanderWeb do
    pipe_through :api

    post "/slack/events", SlackController, :events
    post "/monitoring/alerts", MonitoringController, :create
  end

  # Other scopes may use custom stacks.
  # scope "/api", HelpdeskCommanderWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:helpdesk_commander, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HelpdeskCommanderWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
