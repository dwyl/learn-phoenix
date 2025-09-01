defmodule Hello.Catalog.Product do
  use Ecto.Schema
  import Ecto.Changeset
  alias Hello.Catalog.Category

  schema "products" do
    field :title, :string
    field :description, :string
    field :price, :decimal
    field :views, :integer
    many_to_many :categories, Category, join_through: "product_categories", on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:title, :description, :price, :views])
    |> validate_required([:title, :description, :price, :views])
  end
end
