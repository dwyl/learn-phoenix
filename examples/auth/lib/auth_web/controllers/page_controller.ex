defmodule AuthWeb.PageController do
  use AuthWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
