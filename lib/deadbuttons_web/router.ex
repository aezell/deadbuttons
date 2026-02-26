defmodule DeadbuttonsWeb.Router do
  use DeadbuttonsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DeadbuttonsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DeadbuttonsWeb do
    pipe_through :browser

    live "/", ScanLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", DeadbuttonsWeb do
  #   pipe_through :api
  # end
end
