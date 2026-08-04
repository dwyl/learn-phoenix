defmodule LazyHTML do
  @external_resource "README.md"

  [_, readme_docs, _] =
    "README.md"
    |> File.read!()
    |> String.split("<!-- Docs -->")

  @moduledoc readme_docs

  defstruct [:resource]

  @behaviour Access

  @type t :: %__MODULE__{resource: reference()}

  @doc """
  Parses an HTML document.

  This function expects a complete document, therefore if either of
  `<html>`, `<head>` or `<body>` tags is missing, it will be added,
  which matches the usual browser behaviour. To parse a part of an
  HTML document, use `from_fragment/1` instead.

  ## Examples

      iex> LazyHTML.from_document(~S|<html><head></head><body>Hello world!</body></html>|)
      #LazyHTML<
        1 node
        #1
        <html><head></head><body>Hello world!</body></html>
      >

      iex> LazyHTML.from_document(~S|<div>Hello world!</div>|)
      #LazyHTML<
        1 node
        #1
        <html><head></head><body><div>Hello world!</div></body></html>
      >

  """
  @spec from_document(String.t()) :: t()
  def from_document(html) when is_binary(html) do
    LazyHTML.NIF.from_document(html)
  end

  @doc """
  Parses a segment of an HTML document.

  As opposed to `from_document/1`, this function does not expect a full
  document and does not add any extra tags.

  ## Examples

      iex> LazyHTML.from_fragment(~S|<a class="button">Click me</a>|)
      #LazyHTML<
        1 node
        #1
        <a class="button">Click me</a>
      >

      iex> LazyHTML.from_fragment(~S|<span>Hello</span> <span>world</span>|)
      #LazyHTML<
        3 nodes
        #1
        <span>Hello</span>
        #2
        [whitespace]
        #3
        <span>world</span>
      >

  """
  @spec from_fragment(String.t()) :: t()
  def from_fragment(html) when is_binary(html) do
    LazyHTML.NIF.from_fragment(html)
  end

  @doc ~S'''
  Serializes `lazy_html` as an HTML string.

  ## Options

    * `:skip_whitespace_nodes` - when `true`, ignores text nodes that
      consist entirely of whitespace, usually whitespace between tags.
      Defaults to `false`.

  ## Examples

      iex> lazy_html = LazyHTML.from_document(~S|<html><head></head><body>Hello world!</body></html>|)
      iex> LazyHTML.to_html(lazy_html)
      "<html><head></head><body>Hello world!</body></html>"

      iex> lazy_html = LazyHTML.from_fragment(~S|<span>Hello</span> <span>world</span>|)
      iex> LazyHTML.to_html(lazy_html)
      "<span>Hello</span> <span>world</span>"

      iex> lazy_html =
      ...>   LazyHTML.from_fragment("""
      ...>   <p>
      ...>     <span> Hello </span>
      ...>     <span> world </span>
      ...>   </p>
      ...>   """)
      iex> LazyHTML.to_html(lazy_html, skip_whitespace_nodes: true)
      "<p><span> Hello </span><span> world </span></p>"

  '''
  @spec to_html(t(), keyword()) :: String.t()
  def to_html(%LazyHTML{} = lazy_html, opts \\ []) when is_list(opts) do
    opts = Keyword.validate!(opts, skip_whitespace_nodes: false)

    LazyHTML.NIF.to_html(lazy_html, opts[:skip_whitespace_nodes])
  end

  @doc """
  Builds an Elixir tree data structure representing the `lazy_html`
  document.

  ## Options

    * `:sort_attributes` - when `true`, attributes lists are sorted
      alphabetically by name. Defaults to `false`.

    * `:skip_whitespace_nodes` - when `true`, ignores text nodes that
      consist entirely of whitespace, usually whitespace between tags.
      Defaults to `false`.

  ## Examples

      iex> lazy_html = LazyHTML.from_document(~S|<html><head><title>Page</title></head><body>Hello world</body></html>|)
      iex> LazyHTML.to_tree(lazy_html)
      [{"html", [], [{"head", [], [{"title", [], ["Page"]}]}, {"body", [], ["Hello world"]}]}]

      iex> lazy_html = LazyHTML.from_fragment(~S|<div><!-- Link --><a href="https://elixir-lang.org">Elixir</a></div>|)
      iex> LazyHTML.to_tree(lazy_html)
      [
        {"div", [], [{:comment, " Link "}, {"a", [{"href", "https://elixir-lang.org"}], ["Elixir"]}]}
      ]

  You can get a normalized tree by passing `sort_attributes: true`:

      iex> lazy_html = LazyHTML.from_fragment(~S|<div id="root" class="layout"></div>|)
      iex> LazyHTML.to_tree(lazy_html, sort_attributes: true)
      [{"div", [{"class", "layout"}, {"id", "root"}], []}]

  """
  @spec to_tree(t(), keyword()) :: LazyHTML.Tree.t()
  def to_tree(%LazyHTML{} = lazy_html, opts \\ []) when is_list(opts) do
    opts = Keyword.validate!(opts, sort_attributes: false, skip_whitespace_nodes: false)

    LazyHTML.NIF.to_tree(lazy_html, opts[:sort_attributes], opts[:skip_whitespace_nodes])
  end

  @doc """
  Builds a lazy HTML document from an Elixir tree data structure.

  ## Examples

      iex> tree = [
      ...>   {"html", [], [{"head", [], [{"title", [], ["Page"]}]}, {"body", [], ["Hello world"]}]}
      ...> ]
      iex> LazyHTML.from_tree(tree)
      #LazyHTML<
        1 node
        #1
        <html><head><title>Page</title></head><body>Hello world</body></html>
      >

      iex> tree = [
      ...>   {"div", [], []},
      ...>   {:comment, " Link "},
      ...>   {"a", [{"href", "https://elixir-lang.org"}], ["Elixir"]}
      ...> ]
      iex> LazyHTML.from_tree(tree)
      #LazyHTML<
        3 nodes
        #1
        <div></div>
        #2
        <!-- Link -->
        #3
        <a href="https://elixir-lang.org">Elixir</a>
      >

  """
  @spec from_tree(LazyHTML.Tree.t()) :: t()
  def from_tree(tree) when is_list(tree) do
    LazyHTML.NIF.from_tree(tree)
  end

  @doc ~S'''
  Finds elements in `lazy_html` matching the given CSS selector.

  Since `lazy_html` may have multiple root nodes, the root nodes are
  included in the search and they will appear in the result if they
  match the given selector.

  ## Examples

      iex> lazy_html =
      ...>   LazyHTML.from_fragment("""
      ...>   <div class="layout">
      ...>     <span>Hello</span>
      ...>     <span>world</span>
      ...>   </div>
      ...>   """)
      iex> LazyHTML.query(lazy_html, "span")
      #LazyHTML<
        2 nodes (from selector)
        #1
        <span>Hello</span>
        #2
        <span>world</span>
      >
      iex> LazyHTML.query(lazy_html, ".layout")
      #LazyHTML<
        1 node (from selector)
        #1
        <div class="layout">
          <span>Hello</span>
          <span>world</span>
        </div>
      >

  Note that for each root node, the selector respects its actual
  location in the document. Consequently, if you run one `query/2`
  the returned nodes are not necessarily siblings, which may impact
  a subsequent query:

      iex> lazy_html =
      ...>   LazyHTML.from_fragment("""
      ...>   <div>
      ...>     <span>Hello</span>
      ...>   </div>
      ...>   <div>
      ...>     <span>World</span>
      ...>   </div>
      ...>   """)
      iex> spans = LazyHTML.query(lazy_html, "span")
      #LazyHTML<
        2 nodes (from selector)
        #1
        <span>Hello</span>
        #2
        <span>World</span>
      >
      iex> LazyHTML.query(spans, ":first-child")
      #LazyHTML<
        2 nodes (from selector)
        #1
        <span>Hello</span>
        #2
        <span>World</span>
      >

  In the example above, each of the spans is first child of its
  respective parent, so the second query matches both.
  '''
  @spec query(t(), String.t()) :: t()
  def query(%LazyHTML{} = lazy_html, selector) when is_binary(selector) do
    LazyHTML.NIF.query(lazy_html, selector)
  end

  @doc ~S'''
  Finds elements in `lazy_html` matching the given id.

  This function is similar to `query/2`, but it accepts unescaped id
  string.

  Note that while technically there should be only a single element
  with the given id, if there are multiple elements, all of them are
  included in the result.

  ## Examples

      iex> lazy_html =
      ...>   LazyHTML.from_fragment("""
      ...>   <div>
      ...>     <span id="hello">Hello</span>
      ...>     <span>world</span>
      ...>   </div>
      ...>   """)
      iex> LazyHTML.query_by_id(lazy_html, "hello")
      #LazyHTML<
        1 node (from selector)
        #1
        <span id="hello">Hello</span>
      >

  '''
  @spec query_by_id(t(), String.t()) :: t()
  def query_by_id(%LazyHTML{} = lazy_html, id) when is_binary(id) do
    if id == "" do
      raise ArgumentError, "id cannot be empty"
    end

    LazyHTML.NIF.query_by_id(lazy_html, id)
  end

  @doc ~S'''
  Filters `lazy_html` root nodes, keeping only elements that match
  the given CSS selector.

  ## Examples

      iex> lazy_html = LazyHTML.from_fragment("""
      ...> <span>Hello</span>
      ...> <div>
      ...>   <span>nested</span>
      ...> </div>
      ...> <span>world</span>
      ...> """)
      iex> LazyHTML.filter(lazy_html, "span")
      #LazyHTML<
        2 nodes (from selector)
        #1
        <span>Hello</span>
        #2
        <span>world</span>
      >

  '''
  @spec filter(t(), String.t()) :: t()
  def filter(%LazyHTML{} = lazy_html, selector) when is_binary(selector) do
    LazyHTML.NIF.filter(lazy_html, selector)
  end

  @doc """
  Returns the child_nodes nodes of the root nodes in `lazy_html`.

  ## Examples

      iex> lazy_html = LazyHTML.from_fragment(~S|<div><span>Hello</span> <span>world</span></div>|)
      iex> LazyHTML.child_nodes(lazy_html)
      #LazyHTML<
        3 nodes (from selector)
        #1
        <span>Hello</span>
        #2
        [whitespace]
        #3
        <span>world</span>
      >
      iex> LazyHTML.child_nodes(LazyHTML.child_nodes(lazy_html))
      #LazyHTML<
        2 nodes (from selector)
        #1
        Hello
        #2
        world
      >

  """
  @spec child_nodes(t()) :: t()
  def child_nodes(%LazyHTML{} = lazy_html) do
    LazyHTML.NIF.child_nodes(lazy_html)
  end

  @doc """
  Returns the text content of all nodes in `lazy_html`.

  ## Examples

      iex> lazy_html = LazyHTML.from_fragment(~S|<div><span>Hello</span> <span>world</span></div>|)
      iex> LazyHTML.text(lazy_html)
      "Hello world"

  If you want to get the text for each root node separately, you can
  use `Enum.map/2`:

      iex> lazy_html = LazyHTML.from_fragment(~S|<div><span>Hello</span> <span>world</span></div>|)
      iex> spans = LazyHTML.query(lazy_html, "span")
      #LazyHTML<
        2 nodes (from selector)
        #1
        <span>Hello</span>
        #2
        <span>world</span>
      >
      iex> Enum.map(spans, &LazyHTML.text/1)
      ["Hello", "world"]

  """
  @spec text(t()) :: String.t()
  def text(%LazyHTML{} = lazy_html) do
    LazyHTML.NIF.text(lazy_html)
  end

  @doc ~S'''
  Returns all values of the given attribute on the `lazy_html` root
  nodes.

  ## Examples

      iex> lazy_html =
      ...>   LazyHTML.from_fragment("""
      ...>   <div>
      ...>     <span data-id="1">Hello</span>
      ...>     <span data-id="2">world</span>
      ...>     <span>!</span>
      ...>   </div>
      ...>   """)
      iex> spans = LazyHTML.query(lazy_html, "span")
      iex> LazyHTML.attribute(spans, "data-id")
      ["1", "2"]
      iex> LazyHTML.attribute(spans, "data-other")
      []

  Note that attributes without value, implicitly have an empty value:

      iex> lazy_html = LazyHTML.from_fragment(~S|<div><button disabled>Click me</button></div>|)
      iex> button = LazyHTML.query(lazy_html, "button")
      iex> LazyHTML.attribute(button, "disabled")
      [""]

  '''
  @spec attribute(t(), String.t()) :: list(String.t())
  def attribute(%LazyHTML{} = lazy_html, name) when is_binary(name) do
    LazyHTML.NIF.attribute(lazy_html, name)
  end

  @doc ~S'''
  Returns attribute lists for every root element in `lazy_html`.

  Note that if there are text or comment root nodes, they are ignored,
  and they have no corresponding list in the result.

  ## Examples

      iex> lazy_html =
      ...>   LazyHTML.from_fragment("""
      ...>   <div>
      ...>     <span class="text" data-id="1">Hello</span>
      ...>     <span>world</span>
      ...>   </div>
      ...>   """)
      iex> spans = LazyHTML.query(lazy_html, "span")
      iex> LazyHTML.attributes(spans)
      [
        [{"class", "text"}, {"data-id", "1"}],
        []
      ]

      iex> lazy_html =
      ...>   LazyHTML.from_fragment("""
      ...>   <!-- Comment-->
      ...>   <span class="text">Hello</span>
      ...>   world
      ...>   """)
      iex> LazyHTML.attributes(lazy_html)
      [
        [{"class", "text"}]
      ]

  '''
  @spec attributes(t()) :: list({String.t(), String.t()})
  def attributes(%LazyHTML{} = lazy_html) do
    LazyHTML.NIF.attributes(lazy_html)
  end

  @doc """
  Returns tag name for every root element in `lazy_html`.

  Note that if there are text or comment root nodes, they are ignored,
  and they have no corresponding list in the result.

  ## Examples

      iex> lazy_html = LazyHTML.from_fragment(~S|<div><span>Hello</span> <span>world</span></div>|)
      iex> LazyHTML.tag(lazy_html)
      ["div"]

      iex> lazy_html = LazyHTML.from_fragment(~S|<span>Hello</span> <span>world</span>|)
      iex> LazyHTML.tag(lazy_html)
      ["span", "span"]

  """
  @spec tag(t()) :: list(String.t())
  def tag(%LazyHTML{} = lazy_html) do
    LazyHTML.NIF.tag(lazy_html)
  end

  @doc ~S"""
  Escapes the given string to make a valid HTML text.

  ## Examples

      iex> LazyHTML.html_escape("foo")
      "foo"

      iex> LazyHTML.html_escape("<foo>")
      "&lt;foo&gt;"

      iex> LazyHTML.html_escape("quotes: \" & \'")
      "quotes: &quot; &amp; &#39;"

  """
  @spec html_escape(String.t()) :: String.t()
  def html_escape(string) when is_binary(string) do
    LazyHTML.Tree.html_escape(string)
  end

  # Access

  @impl true
  def fetch(%LazyHTML{} = lazy_html, selector) when is_binary(selector) do
    {:ok, query(lazy_html, selector)}
  end

  @impl true
  def get_and_update(%LazyHTML{}, _index, _update) do
    raise "Access.get_and_update/3 is not supported by LazyHTML"
  end

  @impl true
  def pop(%LazyHTML{}, _index) do
    raise "Access.pop/2 is not supported by LazyHTML"
  end
end

defimpl Inspect, for: LazyHTML do
  import Inspect.Algebra

  def inspect(lazy_html, opts) do
    {nodes, from_selector} = LazyHTML.NIF.nodes(lazy_html)

    info =
      case length(nodes) do
        1 -> "1 node"
        n -> "#{n} nodes"
      end

    info =
      if from_selector do
        info <> " (from selector)"
      else
        info
      end

    inner =
      if nodes == [] do
        empty()
      else
        items = Enum.with_index(nodes, 1)
        {items, last_doc} = apply_limit(items, opts.limit)

        inner =
          concat(Enum.map_intersperse(items, concat(separator(), line()), &node_to_doc(&1, opts)))

        inner = concat([inner, last_doc])
        concat([separator(), nest(concat(line(), inner), 2)])
      end

    force_unfit(
      concat([
        "#LazyHTML<",
        nest(concat([line(), info]), 2),
        inner,
        line(),
        ">"
      ])
    )
  end

  if Application.compile_env(:lazy_html, :inspect_extra_newline, true) do
    defp separator(), do: line()
  else
    defp separator(), do: empty()
  end

  defp apply_limit(items, :infinity), do: {items, empty()}

  defp apply_limit(items, limit) do
    case Enum.split(items, limit) do
      {items, []} -> {items, empty()}
      {items, more} -> {items, concat([separator(), line(), "[#{length(more)} more]"])}
    end
  end

  defp node_to_doc({%LazyHTML{} = node, number}, opts) do
    html_doc =
      node
      |> LazyHTML.to_html()
      |> apply_printable_limit(opts.printable_limit)
      |> String.replace(~r/^\s+/, "[whitespace]")
      |> String.replace(~r/\s+$/, "[whitespace]")
      |> String.split("\n")
      |> Enum.intersperse(line())
      |> concat()

    concat([
      color("##{number}", :atom, opts),
      line(),
      html_doc
    ])
  end

  defp apply_printable_limit(string, :infinity), do: string

  defp apply_printable_limit(string, limit) do
    case String.split_at(string, limit) do
      {left, ""} -> left
      {left, _more} -> left <> "[...]"
    end
  end
end

defimpl Enumerable, for: LazyHTML do
  def count(lazy_html) do
    {:ok, LazyHTML.NIF.num_nodes(lazy_html)}
  end

  def member?(_lazy_html, _element), do: {:error, __MODULE__}

  def slice(_lazy_html), do: {:error, __MODULE__}

  def reduce(%LazyHTML{} = lazy_html, acc, fun) do
    {nodes, _from_selector} = LazyHTML.NIF.nodes(lazy_html)
    Enumerable.reduce(nodes, acc, fun)
  end
end
