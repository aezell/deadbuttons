defmodule DeadbuttonsWeb.PageController do
  use DeadbuttonsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
