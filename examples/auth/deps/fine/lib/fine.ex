defmodule Fine do
  @external_resource "README.md"

  [_, readme_docs, _] =
    "README.md"
    |> File.read!()
    |> String.split("<!-- Docs -->")

  @moduledoc readme_docs

  # Note that include/ is a conventional location for Erlang header
  # files (.hrl) and it is copied to _build/. For this reason, we
  # pick a different name.
  @include_dir Path.expand("c_include")

  @doc """
  Returns the directory with Fine header files.
  """
  @spec include_dir() :: String.t()
  def include_dir(), do: @include_dir
end
