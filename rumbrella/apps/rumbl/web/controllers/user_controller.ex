defmodule Rumbl.UserController do
  use Rumbl.Web, :controller
  plug :authenticate_user when action in [:index, :show]
  alias Rumbl.User

  def index(conn, _params) do
    users = Repo.all(User)
    render conn, "index.html", users: users
  end

  def show(conn, %{"id" => id}) do
    user = Repo.get(User, id)
    render conn, "show.html", user: user
  end

  def new(conn, _params) do
    changeset = User.changeset(%User{})
    render conn, "new.html", changeset: changeset
  end

  def create(conn, %{"user" => user_params}) do
    IO.inspect user_params
    changeset = User.registration_changeset(%User{}, user_params)
    case Repo.insert(changeset) do
      {:ok, user} ->
        conn
        |> Rumbl.Auth.login(user)
        |> put_flash(:info, "#{user.name} created!")
        |> redirect(to: user_path(conn, :index))
      {:error, changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end


  def register(conn, %{"user" => user_params}) do
    email = user_params["username"]
    IO.inspect ">>>>> username: " <> email
    user_params = Map.put(user_params, "name", 
      Enum.at(String.split(user_params["username"], "@"), 0))
    changeset = User.register_changeset(%User{}, user_params)
    # render(conn, "register.html", changeset: changeset)
    case Repo.insert(changeset) do
      {:ok, user} ->
        conn
        |> Rumbl.Auth.login(user)
        |> put_flash(:info, "#{user.name} created!")
        |> redirect(to: user_path(conn, :index))
      {:error, changeset} ->
        IO.inspect changeset
        render(conn, "register.html", changeset: changeset)
    end
  end
end
