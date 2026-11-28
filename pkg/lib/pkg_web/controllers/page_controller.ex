defmodule PkgWeb.PageController do
  use PkgWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
