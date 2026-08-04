defmodule NimbleOptions.Docs do
  @moduledoc false

  def generate(schema, options) when is_list(schema) and is_list(options) do
    nest_level = Keyword.get(options, :nest_level, 0)
    {docs, sections, _level} = build_docs(schema, {[], [], nest_level})
    to_string([Enum.reverse(docs), Enum.reverse(sections)])
  end

  # If the schema is a function, we want to not show anything (it's a recursive
  # function) and "back up" one level since when we got here we already
  # increased the level by one.
  defp build_docs(fun, {docs, sections, level}) when is_function(fun) do
    {docs, sections, level - 1}
  end

  defp build_docs(schema, {docs, sections, level} = acc) do
    if schema[:*] do
      build_docs(schema[:*][:keys], acc)
    else
      Enum.reduce(schema || [], {docs, sections, level}, &maybe_option_doc/2)
    end
  end

  defp build_docs_with_subsection(subsection, schema, {docs, sections, level}) do
    subsection = String.trim_trailing(subsection, "\n") <> "\n\n"

    {item_docs, sections, _level} = build_docs(schema, {[], sections, 0})
    item_section = [subsection | Enum.reverse(item_docs)]

    {docs, [item_section | sections], level}
  end

  defp maybe_option_doc({key, schema}, acc) do
    if schema[:doc] == false do
      acc
    else
      option_doc({key, schema}, acc)
    end
  end

  defp option_doc({key, schema}, {docs, sections, level}) do
    type_str = if type_str = get_type_str(schema), do: " #{type_str}"
    desc_indent = String.duplicate("  ", level + 1)

    description =
      get_required_str(schema)
      |> get_deprecated_str(schema)
      |> get_doc_str(schema)
      |> get_default_str(schema)
      |> case do
        nil -> ""
        parts -> indent_doc(" - " <> parts, desc_indent)
      end

    doc = [String.duplicate("  ", level), "* `#{inspect(key)}`#{type_str}", description, "\n\n"]
    docs = [IO.iodata_to_binary(doc) | docs]

    cond do
      schema[:keys] && schema[:subsection] ->
        build_docs_with_subsection(schema[:subsection], schema[:keys], {docs, sections, level})

      schema[:keys] ->
        {docs, sections, _level} = build_docs(schema[:keys], {docs, sections, level + 1})
        {docs, sections, level}

      true ->
        {docs, sections, level}
    end
  end

  defp space_concat(left, nil), do: left
  defp space_concat(nil, right), do: right
  defp space_concat(left, right), do: left <> " " <> right

  defp get_required_str(schema) do
    if schema[:required], do: "Required."
  end

  defp get_deprecated_str(prev_str, schema) do
    space_concat(
      prev_str,
      schema[:deprecated] && "*This option is deprecated. #{String.trim(schema[:deprecated])}*"
    )
  end

  defp get_doc_str(prev_str, schema) do
    space_concat(prev_str, schema[:doc] && String.trim(schema[:doc]))
  end

  defp get_default_str(prev_str, schema) do
    if Keyword.has_key?(schema, :default) do
      default_str = "The default value is `#{inspect(schema[:default])}`."

      # If the documentation contains multiple lines,
      # the default must be in a trailing line.
      if prev_str && String.contains?(prev_str, ["\r\n", "\n\n"]) do
        prev_str <> "\n\n" <> default_str
      else
        space_concat(prev_str, default_str)
      end
    else
      prev_str
    end
  end

  defp get_type_str(schema) do
    str =
      case Keyword.fetch(schema, :type_doc) do
        {:ok, false} -> nil
        {:ok, type_doc} when is_binary(type_doc) -> type_doc
        :error -> get_raw_type_str(schema[:type])
      end

    if str do
      "(#{str})"
    end
  end

  # Only shows types when they are concise.
  defp get_raw_type_str(nil), do: nil
  defp get_raw_type_str({:custom, _mod, _fun, _args}), do: nil
  defp get_raw_type_str(:mfa), do: nil
  defp get_raw_type_str(:mod_arg), do: nil
  defp get_raw_type_str({:or, _values}), do: nil
  defp get_raw_type_str({:in, _}), do: nil
  defp get_raw_type_str({:fun, arity}), do: "function of arity #{arity}"
  defp get_raw_type_str(:any), do: "`t:term/0`"
  defp get_raw_type_str(:reference), do: "`t:reference/0`"
  defp get_raw_type_str(:pid), do: "`t:pid/0`"
  defp get_raw_type_str(:timeout), do: "`t:timeout/0`"
  defp get_raw_type_str(:boolean), do: "`t:boolean/0`"
  defp get_raw_type_str(:atom), do: "`t:atom/0`"
  defp get_raw_type_str(:integer), do: "`t:integer/0`"
  defp get_raw_type_str(:non_neg_integer), do: "`t:non_neg_integer/0`"
  defp get_raw_type_str(:pos_integer), do: "`t:pos_integer/0`"
  defp get_raw_type_str(:float), do: "`t:float/0`"
  defp get_raw_type_str(:string), do: "`t:String.t/0`"
  defp get_raw_type_str(:keyword_list), do: "`t:keyword/0`"
  defp get_raw_type_str(:non_empty_keyword_list), do: "non-empty `t:keyword/0`"
  defp get_raw_type_str({:map, _keys}), do: "`t:map/0`"
  defp get_raw_type_str({:keyword_list, _keys}), do: "`t:keyword/0`"
  defp get_raw_type_str({:non_empty_keyword_list, _keys}), do: "non-empty `t:keyword/0`"
  defp get_raw_type_str(:map), do: "`t:map/0`"
  defp get_raw_type_str({:struct, struct_type}), do: "struct of type `#{inspect(struct_type)}`"

  defp get_raw_type_str({:list, subtype}) do
    if subtype_str = get_raw_type_str(subtype), do: "list of #{subtype_str}"
  end

  defp get_raw_type_str({:map, key_type, value_type}) do
    with key_type_str when is_binary(key_type_str) <- get_raw_type_str(key_type),
         value_type_str when is_binary(value_type_str) <- get_raw_type_str(value_type) do
      "map of #{key_type_str} keys and #{value_type_str} values"
    end
  end

  defp get_raw_type_str({:tuple, value_types}) do
    value_types =
      value_types
      |> Enum.map(&get_raw_type_str/1)
      |> Enum.join(", ")

    "tuple of #{value_types} values"
  end

  defp indent_doc(text, indent) do
    [head | tail] = String.split(text, ["\r\n", "\n"])

    tail =
      Enum.map(tail, fn
        "" -> "\n"
        str -> [?\n, indent, str]
      end)

    [head | tail]
  end

  def schema_to_spec(schema) do
    schema
    |> Enum.map(fn {key, opt_schema} ->
      typespec =
        Keyword.get_lazy(opt_schema, :type_spec, fn -> type_to_spec(opt_schema[:type]) end)

      quote do: {unquote(key), unquote(typespec)}
    end)
    |> unionize_quoted()
  end

  defp type_to_spec(type) do
    case type do
      :any ->
        quote(do: term())

      :integer ->
        quote(do: integer())

      :non_neg_integer ->
        quote(do: non_neg_integer())

      :pos_integer ->
        quote(do: pos_integer())

      :atom ->
        quote(do: atom())

      :float ->
        quote(do: float())

      :boolean ->
        quote(do: boolean())

      :pid ->
        quote(do: pid())

      :reference ->
        quote(do: reference())

      :timeout ->
        quote(do: timeout())

      :string ->
        quote(do: binary())

      :mfa ->
        quote(do: {module(), atom(), [term()]})

      :mod_arg ->
        quote(do: {module(), [term()]})

      :keyword_list ->
        quote(do: keyword())

      {:keyword_list, _keys} ->
        quote(do: keyword())

      :non_empty_keyword_list ->
        quote(do: keyword())

      {:non_empty_keyword_list, _keys} ->
        quote(do: keyword())

      nil ->
        quote(do: nil)

      :map ->
        quote(do: map())

      {:map, key_type, value_type} ->
        quote(
          do: %{optional(unquote(type_to_spec(key_type))) => unquote(type_to_spec(value_type))}
        )

      {:fun, arity} ->
        function_spec(arity)

      {:in, %Range{first: first, last: last} = range} ->
        # TODO: match on first..last//1 when we depend on Elixir 1.12+
        if Map.get(range, :step) in [nil, 1] do
          quote(do: unquote(first)..unquote(last))
        else
          quote(do: term())
        end

      {:in, _choices} ->
        quote(do: term())

      {:custom, _mod, _fun, _args} ->
        quote(do: term())

      {:list, subtype} ->
        quote(do: [unquote(type_to_spec(subtype))])

      {:or, subtypes} ->
        subtypes |> Enum.map(&type_to_spec/1) |> unionize_quoted()

      {:struct, _struct_name} ->
        quote(do: struct())

      {:tuple, tuple_types} ->
        case Enum.map(tuple_types, &type_to_spec/1) do
          [type1, type2] -> quote(do: {unquote(type1), unquote(type2)})
          types -> quote do: {unquote_splicing(types)}
        end
    end
  end

  defp function_spec(arity) do
    args = List.duplicate(quote(do: term()), arity)

    quote do
      unquote_splicing(args) -> term()
    end
  end

  defp unionize_quoted(specs) do
    specs
    |> Enum.reverse()
    |> Enum.reduce(&quote(do: unquote(&1) | unquote(&2)))
  end
end
