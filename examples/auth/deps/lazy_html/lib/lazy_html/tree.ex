defmodule LazyHTML.Tree do
  @moduledoc """
  This module deals with HTML documents represented as an Elixir tree
  data structure.
  """

  @type t :: list(html_node())
  @type html_node :: html_tag() | html_text() | html_comment()
  @type html_tag :: {String.t(), list(html_attribute()), list(html_node())}
  @type html_attribute :: {String.t(), String.t()}
  @type html_text :: String.t()
  @type html_comment :: {:comment, String.t()}

  @doc ~S'''
  Serializes Elixir tree data structure as an HTML string.

  ## Options

    * `:skip_whitespace_nodes` - when `true`, ignores text nodes that
      consist entirely of whitespace, usually whitespace between tags.
      Defaults to `false`.

  ## Examples

      iex> tree = [
      ...>   {"html", [], [{"head", [], [{"title", [], ["Page"]}]}, {"body", [], ["Hello world"]}]}
      ...> ]
      iex> LazyHTML.Tree.to_html(tree)
      "<html><head><title>Page</title></head><body>Hello world</body></html>"

      iex> tree = [
      ...>   {"div", [], []},
      ...>   {:comment, " Link "},
      ...>   {"a", [{"href", "https://elixir-lang.org"}], ["Elixir"]}
      ...> ]
      iex> LazyHTML.Tree.to_html(tree)
      ~S|<div></div><!-- Link --><a href="https://elixir-lang.org">Elixir</a>|

      iex> tree = [
      ...>   {"p", [],
      ...>    [
      ...>      "\n  ",
      ...>      {"span", [], [" Hello "]},
      ...>      "\n  ",
      ...>      {"span", [], [" world "]},
      ...>      "\n"
      ...>    ]},
      ...>   "\n"
      ...> ]
      iex> LazyHTML.Tree.to_html(tree, skip_whitespace_nodes: true)
      "<p><span> Hello </span><span> world </span></p>"

  '''
  @spec to_html(t(), keyword()) :: String.t()
  def to_html(tree, opts \\ []) when is_list(tree) and is_list(opts) do
    opts = Keyword.validate!(opts, skip_whitespace_nodes: false)

    # We build the html by continuously appending to a result binary.
    # Appending to a binary is optimised by the runtime, so this
    # approach is memory efficient.

    ctx = %{skip_whitespace_nodes: opts[:skip_whitespace_nodes], escape: true}
    to_html(tree, ctx, <<>>)
  end

  @void_tags ~w(
    area base br col embed hr img input link meta source track wbr
    basefont bgsound frame keygen param
  )

  @no_escape_tags ~w(style script xmp iframe noembed noframes plaintext)

  defp to_html([], _ctx, html), do: html

  defp to_html([{tag, attrs, children} | tree], ctx, html) do
    html = <<html::binary, "<", tag::binary>>
    html = append_attrs(attrs, html)

    if tag in @void_tags do
      html = <<html::binary, "/>">>
      to_html(tree, ctx, html)
    else
      html = <<html::binary, ">">>
      escape_children = tag not in @no_escape_tags
      html = to_html(children, %{ctx | escape: escape_children}, html)
      html = <<html::binary, "</", tag::binary, ">">>
      to_html(tree, ctx, html)
    end
  end

  defp to_html([text | tree], ctx, html) when is_binary(text) do
    html = append_text(text, text, 0, ctx, html)
    to_html(tree, ctx, html)
  end

  defp to_html([{:comment, content} | tree], ctx, html) do
    to_html(tree, ctx, <<html::binary, "<!--", content::binary, "-->">>)
  end

  defp append_attrs([], html), do: html

  defp append_attrs([{name, value} | attrs], html) do
    html = <<html::binary, " ", name::binary, ~S/="/>>
    html = append_escaped(value, html)
    html = <<html::binary, ~S/"/>>
    append_attrs(attrs, html)
  end

  defp append_text(<<char, rest::binary>>, text, whitespace_size, ctx, html)
       when char in [?\s, ?\t, ?\n, ?\r],
       do: append_text(rest, text, whitespace_size + 1, ctx, html)

  defp append_text(<<>>, _text, _whitespace_size, ctx, html)
       when ctx.skip_whitespace_nodes,
       do: html

  defp append_text(<<_rest::binary>>, text, _whitespace_size, ctx, html)
       when not ctx.escape,
       do: <<html::binary, text::binary>>

  defp append_text(<<rest::binary>>, text, whitespace_size, ctx, html)
       when ctx.escape,
       do: append_escaped(rest, text, 0, whitespace_size, html)

  # We scan the characters until we run into one that needs escaping.
  # Once we do, we take the whole text chunk up until that point and
  # we append it to the result. This is more efficient than appending
  # each untransformed character individually.
  #
  # Note that we apply the same escaping inside attribute values and
  # tag contents. We could escape less by making it contextual, but
  # we want to match the behaviour of Phoenix.HTML [1].
  #
  # [1]: https://github.com/phoenixframework/phoenix_html/blob/v4.2.1/lib/phoenix_html/engine.ex#L29-L35

  # Note: it is important for this function to be private, so that the
  # Erlang compiler can infer that it is safe to use mutating appends
  # on the underlying binary and maximise optimisations [1].
  #
  # [1]: https://github.com/dashbitco/lazy_html/pull/19
  defp append_escaped(text, html) do
    append_escaped(text, text, 0, 0, html)
  end

  defp append_escaped(<<>>, text, 0 = _offset, _size, html) do
    # We scanned the whole text and there were no characters to escape,
    # so we append the whole text.
    <<html::binary, text::binary>>
  end

  defp append_escaped(<<>>, text, offset, size, html) do
    chunk = binary_part(text, offset, size)
    <<html::binary, chunk::binary>>
  end

  escapes = [
    {?&, "&amp;"},
    {?<, "&lt;"},
    {?>, "&gt;"},
    {?", "&quot;"},
    {?', "&#39;"}
  ]

  for {char, escaped} <- escapes do
    defp append_escaped(<<unquote(char), rest::binary>>, text, offset, size, html) do
      chunk = binary_part(text, offset, size)
      html = <<html::binary, chunk::binary, unquote(escaped)>>
      append_escaped(rest, text, offset + size + 1, 0, html)
    end
  end

  defp append_escaped(<<_char, rest::binary>>, text, offset, size, html) do
    append_escaped(rest, text, offset, size + 1, html)
  end

  @doc """
  Performs a depth-first, pre-order traversal of the given tree.

  This function traverses the tree without modifying it, check `postwalk/2` and
  `postwalk/3` if you need to modify the tree.
  """
  @spec prereduce(
          t(),
          acc,
          (html_node(), acc -> acc)
        ) :: acc
        when acc: term()
  def prereduce(tree, acc, fun)

  def prereduce([{tag, attrs, children} | rest], acc, fun) do
    acc = fun.({tag, attrs, children}, acc)
    acc = prereduce(children, acc, fun)
    prereduce(rest, acc, fun)
  end

  def prereduce([node | rest], acc, fun) do
    acc = fun.(node, acc)
    prereduce(rest, acc, fun)
  end

  def prereduce([], acc, _fun), do: acc

  @doc """
  Performs a depth-first, post-order traversal of the given tree.

  This function traverses the tree without modifying it, check `postwalk/2` and
  `postwalk/3` if you need to modify the tree.
  """
  @spec postreduce(
          t(),
          acc,
          (html_node(), acc -> acc)
        ) :: acc
        when acc: term()
  def postreduce(tree, acc, fun)

  def postreduce([], acc, _fun), do: acc

  def postreduce([node | rest], acc, fun) do
    acc = postreduce(node, acc, fun)
    postreduce(rest, acc, fun)
  end

  def postreduce({tag, attrs, children}, acc, fun) do
    acc = postreduce(children, acc, fun)
    fun.({tag, attrs, children}, acc)
  end

  def postreduce(node, acc, fun) do
    fun.(node, acc)
  end

  @doc """
  Performs a depth-first, post-order traversal of the given tree.

  The mapper `fun` can return a list of nodes to replace the given
  node. In order to remove a node, return an empty list.
  """
  @spec postwalk(
          t(),
          acc,
          (html_node(), acc -> {html_node() | list(html_node()), acc})
        ) :: {t(), acc}
        when acc: term()
  def postwalk(tree, acc, fun), do: do_postwalk(tree, acc, fun)

  defp do_postwalk([], acc, _fun), do: {[], acc}

  defp do_postwalk([node | rest], acc, fun) do
    case do_postwalk(node, acc, fun) do
      {nodes, acc} when is_list(nodes) ->
        {rest, acc} = do_postwalk(rest, acc, fun)
        {nodes ++ rest, acc}

      {node, acc} ->
        {rest, acc} = do_postwalk(rest, acc, fun)
        {[node | rest], acc}
    end
  end

  defp do_postwalk({tag, attrs, children}, acc, fun) do
    {children, acc} = do_postwalk(children, acc, fun)
    fun.({tag, attrs, children}, acc)
  end

  defp do_postwalk(node, acc, fun) do
    fun.(node, acc)
  end

  @doc """
  Same a `postwalk/3`, but with no accumulator.
  """
  @spec postwalk(t(), (html_node() -> html_node() | list(html_node()))) :: t()
  def postwalk(tree, fun) do
    {tree, {}} =
      postwalk(tree, {}, fn node, {} ->
        {fun.(node), {}}
      end)

    tree
  end

  @doc false
  def html_escape(string), do: append_escaped(string, "")
end
