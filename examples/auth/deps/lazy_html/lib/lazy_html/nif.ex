defmodule LazyHTML.NIF do
  @moduledoc false

  @on_load :__on_load__

  def __on_load__ do
    path = :filename.join(:code.priv_dir(:lazy_html), ~c"liblazy_html")

    case :erlang.load_nif(path, 0) do
      :ok -> :ok
      {:error, reason} -> raise "failed to load NIF library, reason: #{inspect(reason)}"
    end
  end

  def from_document(_html), do: err!()
  def from_fragment(_html), do: err!()
  def to_html(_lazy_html, _skip_whitespace_nodes), do: err!()
  def to_tree(_lazy_html, _sort_attributes, _skip_whitespace_nodes), do: err!()
  def from_tree(_tree), do: err!()
  def query(_lazy_html, _css_selector), do: err!()
  def filter(_lazy_html, _css_selector), do: err!()
  def query_by_id(_lazy_html, _id), do: err!()
  def child_nodes(_lazy_html), do: err!()
  def text(_lazy_html), do: err!()
  def attribute(_lazy_html, _name), do: err!()
  def attributes(_lazy_html), do: err!()
  def tag(_lazy_html), do: err!()
  def nodes(_lazy_html), do: err!()
  def num_nodes(_lazy_html), do: err!()

  defp err!(), do: :erlang.nif_error(:not_loaded)
end
