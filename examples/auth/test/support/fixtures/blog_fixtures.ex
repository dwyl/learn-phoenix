defmodule MyApp.BlogFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `MyApp.Blog` context.
  """

  @doc """
  Generate a post.
  """
  def post_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        body: "some body",
        title: "some title"
      })

    {:ok, post} = MyApp.Blog.create_post(scope, attrs)
    post
  end
end
