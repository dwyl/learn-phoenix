defmodule Auth.BlogFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Auth.Blog` context.
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

    {:ok, post} = Auth.Blog.create_post(scope, attrs)
    post
  end
end
