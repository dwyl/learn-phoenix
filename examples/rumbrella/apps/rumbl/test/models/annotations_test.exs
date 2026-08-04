defmodule Rumbl.AnnotationsTest do
  use Rumbl.ModelCase

  alias Rumbl.Annotations

  @valid_attrs %{at: 42, body: "some content"}
  @invalid_attrs %{}

  test "changeset with valid attributes" do
    changeset = Annotations.changeset(%Annotations{}, @valid_attrs)
    assert changeset.valid?
  end

  test "changeset with invalid attributes" do
    changeset = Annotations.changeset(%Annotations{}, @invalid_attrs)
    refute changeset.valid?
  end
end
