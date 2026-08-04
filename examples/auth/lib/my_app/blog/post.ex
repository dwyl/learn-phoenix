defmodule MyApp.Blog.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    field :title, :string
    field :body, :string
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(post, attrs, user_scope) do
    post
    |> cast(attrs, [:title, :body])
    |> validate_required([:title, :body])
    |> put_change(:user_id, user_scope.user.id)
  end
end
