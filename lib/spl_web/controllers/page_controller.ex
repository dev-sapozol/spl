defmodule SplWeb.PageController do
  use SplWeb, :controller

  def home(conn, _params) do
    text(conn, "¡Bienvenido a Spl!")
  end
end
