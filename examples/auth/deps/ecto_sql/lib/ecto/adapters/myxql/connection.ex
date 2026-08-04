if Code.ensure_loaded?(MyXQL) do
  defmodule Ecto.Adapters.MyXQL.Connection do
    @moduledoc false
    alias Ecto.Adapters.SQL

    @behaviour Ecto.Adapters.SQL.Connection

    ## Connection

    @impl true
    def child_spec(opts) do
      MyXQL.child_spec(opts)
    end

    ## Query

    @impl true
    def prepare_execute(conn, name, sql, params, opts) do
      ensure_list_params!(params)
      MyXQL.prepare_execute(conn, name, sql, params, opts)
    end

    @impl true
    def query(conn, sql, params, opts) do
      ensure_list_params!(params)
      opts = Keyword.put_new(opts, :query_type, :binary_then_text)
      MyXQL.query(conn, sql, params, opts)
    end

    @impl true
    def query_many(conn, sql, params, opts) do
      ensure_list_params!(params)
      opts = Keyword.put_new(opts, :query_type, :text)
      MyXQL.query_many(conn, sql, params, opts)
    end

    @impl true
    def execute(conn, query, params, opts) do
      ensure_list_params!(params)

      case MyXQL.execute(conn, query, params, opts) do
        {:ok, _, result} -> {:ok, result}
        {:error, _} = error -> error
      end
    end

    @impl true
    def stream(conn, sql, params, opts) do
      ensure_list_params!(params)
      MyXQL.stream(conn, sql, params, opts)
    end

    defp ensure_list_params!(params) do
      unless is_list(params) do
        raise ArgumentError, "expected params to be a list, got: #{inspect(params)}"
      end
    end

    @quotes ~w(" ' `)

    @impl true
    def to_constraints(%MyXQL.Error{mysql: %{name: :ER_DUP_ENTRY}, message: message}, opts) do
      with [_, quoted] <- :binary.split(message, " for key "),
           [_, index | _] <- :binary.split(quoted, @quotes, [:global]) do
        [unique: strip_source(index, opts[:source])]
      else
        _ -> []
      end
    end

    def to_constraints(%MyXQL.Error{mysql: %{name: name}, message: message}, _opts)
        when name in [:ER_ROW_IS_REFERENCED_2, :ER_NO_REFERENCED_ROW_2] do
      with [_, quoted] <- :binary.split(message, [" CONSTRAINT ", " FOREIGN KEY "]),
           [_, index | _] <- :binary.split(quoted, @quotes, [:global]) do
        [foreign_key: index]
      else
        _ -> []
      end
    end

    def to_constraints(
          %MyXQL.Error{mysql: %{name: :ER_CHECK_CONSTRAINT_VIOLATED}, message: message},
          _opts
        ) do
      with [_, quoted] <- :binary.split(message, ["Check constraint "]),
           [_, constraint | _] <- :binary.split(quoted, @quotes, [:global]) do
        [check: constraint]
      else
        _ -> []
      end
    end

    def to_constraints(_, _),
      do: []

    defp strip_source(name, nil), do: name
    defp strip_source(name, source), do: String.trim_leading(name, "#{source}.")

    ## Query

    @parent_as __MODULE__
    alias Ecto.Query.{BooleanExpr, ByExpr, JoinExpr, QueryExpr, WithExpr}

    @impl true
    def all(query, as_prefix \\ []) do
      sources = create_names(query, as_prefix)

      cte = cte(query, sources)
      from = from(query, sources)
      select = select(query, sources)
      join = join(query, sources)
      where = where(query, sources)
      group_by = group_by(query, sources)
      having = having(query, sources)
      window = window(query, sources)
      combinations = combinations(query, as_prefix)
      order_by = order_by(query, sources)
      limit = limit(query, sources)
      offset = offset(query, sources)
      lock = lock(query, sources)

      [
        cte,
        select,
        from,
        join,
        where,
        group_by,
        having,
        window,
        combinations,
        order_by,
        limit,
        offset | lock
      ]
    end

    @impl true
    def update_all(query, prefix \\ nil) do
      %{from: %{source: source}, select: select} = query

      if select do
        error!(nil, ":select is not supported in update_all by MySQL")
      end

      sources = create_names(query, [])
      cte = cte(query, sources)
      {from, name} = get_source(query, sources, 0, source)

      fields =
        if prefix do
          update_fields(:on_conflict, query, sources)
        else
          update_fields(:update, query, sources)
        end

      {join, wheres} = using_join(query, :update_all, sources)
      prefix = prefix || ["UPDATE ", from, " AS ", name, join, " SET "]
      where = where(%{query | wheres: wheres ++ query.wheres}, sources)

      [cte, prefix, fields | where]
    end

    @impl true
    def delete_all(query) do
      if query.select do
        error!(nil, ":select is not supported in delete_all by MySQL")
      end

      sources = create_names(query, [])
      cte = cte(query, sources)
      {_, name, _} = elem(sources, 0)

      from = from(query, sources)
      join = join(query, sources)
      where = where(query, sources)

      [cte, "DELETE ", name, ".*", from, join | where]
    end

    @impl true
    def insert(prefix, table, header, rows, on_conflict, [], []) do
      fields = quote_names(header)

      [
        "INSERT INTO ",
        quote_table(prefix, table),
        " (",
        fields,
        ") ",
        insert_all(rows) | on_conflict(on_conflict, header)
      ]
    end

    def insert(_prefix, _table, _header, _rows, _on_conflict, _returning, []) do
      error!(nil, ":returning is not supported in insert/insert_all by MySQL")
    end

    def insert(_prefix, _table, _header, _rows, _on_conflict, _returning, _placeholders) do
      error!(nil, ":placeholders is not supported by MySQL")
    end

    defp on_conflict({_, _, [_ | _]}, _header) do
      error!(nil, ":conflict_target is not supported in insert/insert_all by MySQL")
    end

    defp on_conflict({:raise, _, []}, _header) do
      []
    end

    defp on_conflict({:nothing, _, []}, [field | _]) do
      quoted = quote_name(field)
      [" ON DUPLICATE KEY UPDATE ", quoted, " = " | quoted]
    end

    defp on_conflict({fields, _, []}, _header) when is_list(fields) do
      [
        " ON DUPLICATE KEY UPDATE "
        | Enum.map_intersperse(fields, ?,, fn field ->
            quoted = quote_name(field)
            [quoted, " = VALUES(", quoted, ?)]
          end)
      ]
    end

    defp on_conflict({%{wheres: []} = query, _, []}, _header) do
      [" ON DUPLICATE KEY " | update_all(query, "UPDATE ")]
    end

    defp on_conflict({_query, _, []}, _header) do
      error!(
        nil,
        "Using a query with :where in combination with the :on_conflict option is not supported by MySQL"
      )
    end

    defp insert_all(rows) when is_list(rows) do
      [
        "VALUES ",
        Enum.map_intersperse(rows, ?,, fn row ->
          [?(, Enum.map_intersperse(row, ?,, &insert_all_value/1), ?)]
        end)
      ]
    end

    defp insert_all(%Ecto.Query{} = query) do
      [?(, all(query), ?)]
    end

    defp insert_all_value(nil), do: "DEFAULT"
    defp insert_all_value({%Ecto.Query{} = query, _params_counter}), do: [?(, all(query), ?)]
    defp insert_all_value(_), do: ~c"?"

    @impl true
    def update(prefix, table, fields, filters, _returning) do
      fields = Enum.map_intersperse(fields, ", ", &[quote_name(&1), " = ?"])

      filters =
        Enum.map_intersperse(filters, " AND ", fn
          {field, nil} ->
            [quote_name(field), " IS NULL"]

          {field, _value} ->
            [quote_name(field), " = ?"]
        end)

      ["UPDATE ", quote_table(prefix, table), " SET ", fields, " WHERE " | filters]
    end

    @impl true
    def delete(prefix, table, filters, _returning) do
      filters =
        Enum.map_intersperse(filters, " AND ", fn
          {field, nil} ->
            [quote_name(field), " IS NULL"]

          {field, _value} ->
            [quote_name(field), " = ?"]
        end)

      ["DELETE FROM ", quote_table(prefix, table), " WHERE " | filters]
    end

    @impl true
    # DB explain opts, except format, are deprecated.
    # See Notes at https://dev.mysql.com/doc/refman/5.7/en/explain.html
    def explain_query(conn, query, params, opts) do
      {explain_opts, opts} = Keyword.split(opts, ~w[format]a)
      map_format? = {:format, :map} in explain_opts

      case query(conn, build_explain_query(query, explain_opts), params, opts) do
        {:ok, %MyXQL.Result{rows: rows}} when map_format? ->
          json_library = MyXQL.json_library()
          decoded_result = Enum.map(rows, &json_library.decode!(&1))
          {:ok, decoded_result}

        {:ok, %MyXQL.Result{} = result} ->
          {:ok, SQL.format_table(result)}

        error ->
          error
      end
    end

    def build_explain_query(query, []) do
      ["EXPLAIN ", query]
      |> IO.iodata_to_binary()
    end

    def build_explain_query(query, format: value) do
      ["EXPLAIN #{String.upcase("#{format_to_sql(value)}")} ", query]
      |> IO.iodata_to_binary()
    end

    ## Query generation

    binary_ops = [
      ==: " = ",
      !=: " != ",
      <=: " <= ",
      >=: " >= ",
      <: " < ",
      >: " > ",
      +: " + ",
      -: " - ",
      *: " * ",
      /: " / ",
      and: " AND ",
      or: " OR ",
      like: " LIKE "
    ]

    @binary_ops Keyword.keys(binary_ops)

    Enum.map(binary_ops, fn {op, str} ->
      defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
    end)

    defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

    defp select(%{select: %{fields: fields}, distinct: distinct} = query, sources) do
      ["SELECT ", distinct(distinct, sources, query) | select(fields, sources, query)]
    end

    defp distinct(nil, _sources, _query), do: []
    defp distinct(%ByExpr{expr: true}, _sources, _query), do: "DISTINCT "
    defp distinct(%ByExpr{expr: false}, _sources, _query), do: []

    defp distinct(%ByExpr{expr: exprs}, _sources, query) when is_list(exprs) do
      error!(query, "DISTINCT with multiple columns is not supported by MySQL")
    end

    defp select([], _sources, _query),
      do: "TRUE"

    defp select(fields, sources, query) do
      Enum.map_intersperse(fields, ", ", fn
        {:&, _, [idx]} ->
          case elem(sources, idx) do
            {nil, source, nil} ->
              error!(
                query,
                "MySQL adapter does not support selecting all fields from fragment #{source}. " <>
                  "Please specify exactly which fields you want to select"
              )

            {source, _, nil} ->
              error!(
                query,
                "MySQL adapter does not support selecting all fields from #{source} without a schema. " <>
                  "Please specify a schema or specify exactly which fields you want to select"
              )

            {_, source, _} ->
              source
          end

        {key, value} ->
          [expr(value, sources, query), " AS ", quote_name(key)]

        value ->
          expr(value, sources, query)
      end)
    end

    defp from(%{from: %{source: source, hints: hints}} = query, sources) do
      {from, name} = get_source(query, sources, 0, source)
      [" FROM ", from, " AS ", name | Enum.map(hints, &[?\s | &1])]
    end

    defp cte(%{with_ctes: %WithExpr{queries: [_ | _]}} = query, sources) do
      %{with_ctes: with} = query
      recursive_opt = if with.recursive, do: "RECURSIVE ", else: ""
      ctes = Enum.map_intersperse(with.queries, ", ", &cte_expr(&1, sources, query))
      ["WITH ", recursive_opt, ctes, " "]
    end

    defp cte(%{with_ctes: _}, _), do: []

    defp cte_expr({_name, %{materialized: materialized}, _cte}, _sources, query)
         when is_boolean(materialized) do
      error!(query, "MySQL adapter does not support materialized CTEs")
    end

    defp cte_expr({name, opts, cte}, sources, query) do
      operation_opt = Map.get(opts, :operation)

      [quote_name(name), " AS ", cte_query(cte, sources, query, operation_opt)]
    end

    defp cte_query(query, sources, parent_query, nil) do
      cte_query(query, sources, parent_query, :all)
    end

    defp cte_query(%Ecto.Query{} = query, sources, parent_query, :all) do
      query = put_in(query.aliases[@parent_as], {parent_query, sources})
      ["(", all(query, subquery_as_prefix(sources)), ")"]
    end

    defp cte_query(%Ecto.Query{} = query, _sources, _parent_query, operation) do
      error!(
        query,
        "MySQL adapter does not support data-modifying CTEs (operation: #{operation})"
      )
    end

    defp cte_query(%QueryExpr{expr: expr}, sources, query, _operation) do
      expr(expr, sources, query)
    end

    defp update_fields(type, %{updates: updates} = query, sources) do
      fields =
        for(
          %{expr: expr} <- updates,
          {op, kw} <- expr,
          {key, value} <- kw,
          do: update_op(op, update_key(type, key, query, sources), value, sources, query)
        )

      Enum.intersperse(fields, ", ")
    end

    defp update_key(:update, key, %{from: from} = query, sources) do
      {_from, name} = get_source(query, sources, 0, from)

      [name, ?. | quote_name(key)]
    end

    defp update_key(:on_conflict, key, _query, _sources) do
      quote_name(key)
    end

    defp update_op(:set, quoted_key, value, sources, query) do
      [quoted_key, " = " | expr(value, sources, query)]
    end

    defp update_op(:inc, quoted_key, value, sources, query) do
      [quoted_key, " = ", quoted_key, " + " | expr(value, sources, query)]
    end

    defp update_op(command, _quoted_key, _value, _sources, query) do
      error!(query, "Unknown update operation #{inspect(command)} for MySQL")
    end

    defp using_join(%{joins: []}, _kind, _sources), do: {[], []}

    defp using_join(%{joins: joins} = query, kind, sources) do
      froms =
        Enum.map_intersperse(joins, ", ", fn
          %JoinExpr{source: %Ecto.SubQuery{params: [_ | _]}} ->
            error!(
              query,
              "MySQL adapter does not support subqueries with parameters in update_all/delete_all joins"
            )

          %JoinExpr{qual: :inner, ix: ix, source: source} ->
            {join, name} = get_source(query, sources, ix, source)
            [join, " AS " | name]

          %JoinExpr{qual: qual} ->
            error!(query, "MySQL adapter supports only inner joins on #{kind}, got: `#{qual}`")
        end)

      wheres =
        for %JoinExpr{on: %QueryExpr{expr: value} = expr} <- joins,
            value != true,
            do: expr |> Map.put(:__struct__, BooleanExpr) |> Map.put(:op, :and)

      {[?,, ?\s | froms], wheres}
    end

    defp join(%{joins: []}, _sources), do: []

    defp join(%{joins: joins} = query, sources) do
      Enum.map(joins, fn
        %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix, source: source, hints: hints} ->
          {join, name} = get_source(query, sources, ix, source)

          [
            join_qual(qual, query),
            join,
            " AS ",
            name,
            Enum.map(hints, &[?\s | &1]) | join_on(qual, expr, sources, query)
          ]
      end)
    end

    defp join_on(:cross, true, _sources, _query), do: []
    defp join_on(:cross_lateral, true, _sources, _query), do: []
    defp join_on(_qual, expr, sources, query), do: [" ON " | expr(expr, sources, query)]

    defp join_qual(:inner, _), do: " INNER JOIN "
    defp join_qual(:inner_lateral, _), do: " INNER JOIN LATERAL "
    defp join_qual(:left, _), do: " LEFT OUTER JOIN "
    defp join_qual(:left_lateral, _), do: " LEFT OUTER JOIN LATERAL "
    defp join_qual(:right, _), do: " RIGHT OUTER JOIN "
    defp join_qual(:full, _), do: " FULL OUTER JOIN "
    defp join_qual(:cross, _), do: " CROSS JOIN "
    defp join_qual(:cross_lateral, _), do: " CROSS JOIN LATERAL "

    defp join_qual(qual, query),
      do: error!(query, "join qualifier #{inspect(qual)} is not supported in the MySQL adapter")

    defp where(%{wheres: wheres} = query, sources) do
      boolean(" WHERE ", wheres, sources, query)
    end

    defp having(%{havings: havings} = query, sources) do
      boolean(" HAVING ", havings, sources, query)
    end

    defp group_by(%{group_bys: []}, _sources), do: []

    defp group_by(%{group_bys: group_bys} = query, sources) do
      [
        " GROUP BY "
        | Enum.map_intersperse(group_bys, ", ", fn %ByExpr{expr: expr} ->
            Enum.map_intersperse(expr, ", ", &top_level_expr(&1, sources, query))
          end)
      ]
    end

    defp window(%{windows: []}, _sources), do: []

    defp window(%{windows: windows} = query, sources) do
      [
        " WINDOW "
        | Enum.map_intersperse(windows, ", ", fn {name, %{expr: kw}} ->
            [quote_name(name), " AS " | window_exprs(kw, sources, query)]
          end)
      ]
    end

    defp window_exprs(kw, sources, query) do
      [?(, Enum.map_intersperse(kw, ?\s, &window_expr(&1, sources, query)), ?)]
    end

    defp window_expr({:partition_by, fields}, sources, query) do
      ["PARTITION BY " | Enum.map_intersperse(fields, ", ", &expr(&1, sources, query))]
    end

    defp window_expr({:order_by, fields}, sources, query) do
      ["ORDER BY " | Enum.map_intersperse(fields, ", ", &order_by_expr(&1, sources, query))]
    end

    defp window_expr({:frame, {:fragment, _, _} = fragment}, sources, query) do
      expr(fragment, sources, query)
    end

    defp order_by(%{order_bys: []}, _sources), do: []

    defp order_by(%{order_bys: order_bys} = query, sources) do
      [
        " ORDER BY "
        | Enum.map_intersperse(order_bys, ", ", fn %ByExpr{expr: expr} ->
            Enum.map_intersperse(expr, ", ", &order_by_expr(&1, sources, query))
          end)
      ]
    end

    defp order_by_expr({dir, expr}, sources, query) do
      str = top_level_expr(expr, sources, query)

      case dir do
        :asc -> str
        :desc -> [str | " DESC"]
        _ -> error!(query, "#{dir} is not supported in ORDER BY in MySQL")
      end
    end

    defp limit(%{limit: nil}, _sources), do: []

    defp limit(%{limit: %{with_ties: true}} = query, _sources) do
      error!(query, "MySQL adapter does not support the `:with_ties` limit option")
    end

    defp limit(%{limit: %{expr: expr}} = query, sources) do
      [" LIMIT " | expr(expr, sources, query)]
    end

    defp offset(%{offset: nil}, _sources), do: []

    defp offset(%{offset: %QueryExpr{expr: expr}} = query, sources) do
      [" OFFSET " | expr(expr, sources, query)]
    end

    defp combinations(%{combinations: combinations}, as_prefix) do
      Enum.map(combinations, fn
        {:union, query} -> [" UNION (", all(query, as_prefix), ")"]
        {:union_all, query} -> [" UNION ALL (", all(query, as_prefix), ")"]
        {:except, query} -> [" EXCEPT (", all(query, as_prefix), ")"]
        {:except_all, query} -> [" EXCEPT ALL (", all(query, as_prefix), ")"]
        {:intersect, query} -> [" INTERSECT (", all(query, as_prefix), ")"]
        {:intersect_all, query} -> [" INTERSECT ALL (", all(query, as_prefix), ")"]
      end)
    end

    defp lock(%{lock: nil}, _sources), do: []
    defp lock(%{lock: binary}, _sources) when is_binary(binary), do: [?\s | binary]
    defp lock(%{lock: expr} = query, sources), do: [?\s | expr(expr, sources, query)]

    defp boolean(_name, [], _sources, _query), do: []

    defp boolean(name, [%{expr: expr, op: op} | query_exprs], sources, query) do
      [
        name,
        Enum.reduce(query_exprs, {op, paren_expr(expr, sources, query)}, fn
          %BooleanExpr{expr: expr, op: op}, {op, acc} ->
            {op, [acc, operator_to_boolean(op) | paren_expr(expr, sources, query)]}

          %BooleanExpr{expr: expr, op: op}, {_, acc} ->
            {op, [?(, acc, ?), operator_to_boolean(op) | paren_expr(expr, sources, query)]}
        end)
        |> elem(1)
      ]
    end

    defp operator_to_boolean(:and), do: " AND "
    defp operator_to_boolean(:or), do: " OR "

    defp parens_for_select([first_expr | _] = expr) do
      if is_binary(first_expr) and String.match?(first_expr, ~r/^\s*select/i) do
        [?(, expr, ?)]
      else
        expr
      end
    end

    defp paren_expr(expr, sources, query) do
      [?(, expr(expr, sources, query), ?)]
    end

    defp top_level_expr(%Ecto.SubQuery{query: query}, sources, parent_query) do
      combinations =
        Enum.map(query.combinations, fn {type, combination_query} ->
          {type, put_in(combination_query.aliases[@parent_as], {parent_query, sources})}
        end)

      query = put_in(query.combinations, combinations)
      query = put_in(query.aliases[@parent_as], {parent_query, sources})
      [all(query, subquery_as_prefix(sources))]
    end

    defp top_level_expr(other, sources, parent_query) do
      expr(other, sources, parent_query)
    end

    defp expr({:^, [], [_ix]}, _sources, _query) do
      ~c"?"
    end

    defp expr({{:., _, [{:parent_as, _, [as]}, field]}, _, []}, _sources, query)
         when is_atom(field) or is_binary(field) do
      {ix, sources} = get_parent_sources_ix(query, as)
      {_, name, _} = elem(sources, ix)
      [name, ?. | quote_name(field)]
    end

    defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query)
         when is_atom(field) or is_binary(field) do
      {_, name, _} = elem(sources, idx)
      [name, ?. | quote_name(field)]
    end

    defp expr({:&, _, [idx]}, sources, _query) do
      {_, source, _} = elem(sources, idx)
      source
    end

    defp expr({:in, _, [_left, []]}, _sources, _query) do
      "false"
    end

    defp expr({:in, _, [left, right]}, sources, query) when is_list(right) do
      args = Enum.map_intersperse(right, ?,, &expr(&1, sources, query))
      [expr(left, sources, query), " IN (", args, ?)]
    end

    defp expr({:in, _, [_, {:^, _, [_, 0]}]}, _sources, _query) do
      "false"
    end

    defp expr({:in, _, [left, {:^, _, [_, length]}]}, sources, query) do
      args = Enum.intersperse(List.duplicate(??, length), ?,)
      [expr(left, sources, query), " IN (", args, ?)]
    end

    defp expr({:in, _, [left, %Ecto.SubQuery{} = subquery]}, sources, query) do
      [expr(left, sources, query), " IN ", expr(subquery, sources, query)]
    end

    defp expr({:in, _, [left, right]}, sources, query) do
      [expr(left, sources, query), " = ANY(", expr(right, sources, query), ?)]
    end

    defp expr({:is_nil, _, [arg]}, sources, query) do
      [expr(arg, sources, query) | " IS NULL"]
    end

    defp expr({:not, _, [expr]}, sources, query) do
      ["NOT (", expr(expr, sources, query), ?)]
    end

    defp expr({:filter, _, _}, _sources, query) do
      error!(query, "MySQL adapter does not support aggregate filters")
    end

    defp expr(%Ecto.SubQuery{} = subquery, sources, parent_query) do
      [?(, top_level_expr(subquery, sources, parent_query), ?)]
    end

    defp expr({:fragment, _, [kw]}, _sources, query) when is_list(kw) or tuple_size(kw) == 3 do
      error!(query, "MySQL adapter does not support keyword or interpolated fragments")
    end

    defp expr({:fragment, _, parts}, sources, query) do
      Enum.map(parts, fn
        {:raw, part} -> part
        {:expr, expr} -> expr(expr, sources, query)
      end)
      |> parens_for_select
    end

    defp expr({:values, _, [types, _idx, num_rows]}, _, query) do
      [?(, values_list(types, num_rows, query), ?)]
    end

    defp expr({:identifier, _, [literal]}, _sources, _query) do
      quote_name(literal)
    end

    defp expr({:constant, _, [literal]}, _sources, _query) when is_binary(literal) do
      [?', escape_string(literal), ?']
    end

    defp expr({:constant, _, [literal]}, _sources, _query) when is_number(literal) do
      [to_string(literal)]
    end

    defp expr({:splice, _, [{:^, _, [_, length]}]}, _sources, _query) do
      Enum.intersperse(List.duplicate(??, length), ?,)
    end

    defp expr({:selected_as, _, [name]}, _sources, _query) do
      [quote_name(name)]
    end

    defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
      [
        "date_add(",
        expr(datetime, sources, query),
        ", ",
        interval(count, interval, sources, query) | ")"
      ]
    end

    defp expr({:date_add, _, [date, count, interval]}, sources, query) do
      [
        "CAST(date_add(",
        expr(date, sources, query),
        ", ",
        interval(count, interval, sources, query) | ") AS date)"
      ]
    end

    defp expr({:ilike, _, [_, _]}, _sources, query) do
      error!(query, "ilike is not supported by MySQL")
    end

    defp expr({:over, _, [agg, name]}, sources, query) when is_atom(name) do
      aggregate = expr(agg, sources, query)
      [aggregate, " OVER " | quote_name(name)]
    end

    defp expr({:over, _, [agg, kw]}, sources, query) do
      aggregate = expr(agg, sources, query)
      [aggregate, " OVER " | window_exprs(kw, sources, query)]
    end

    defp expr({:{}, _, elems}, sources, query) do
      [?(, Enum.map_intersperse(elems, ?,, &expr(&1, sources, query)), ?)]
    end

    defp expr({:count, _, []}, _sources, _query), do: "count(*)"

    defp expr({:json_extract_path, _, [expr, path]}, sources, query) do
      path =
        Enum.map(path, fn
          binary when is_binary(binary) ->
            [?., ?", escape_json_key(binary), ?"]

          integer when is_integer(integer) ->
            "[#{integer}]"

          _ ->
            error!(
              query,
              "MySQL adapter does not support references to source fields inside of `json_extract_path`"
            )
        end)

      ["json_extract(", expr(expr, sources, query), ", '$", path, "')"]
    end

    defp expr({fun, _, args}, sources, query) when is_atom(fun) and is_list(args) do
      {modifier, args} =
        case args do
          [rest, :distinct] -> {"DISTINCT ", [rest]}
          _ -> {[], args}
        end

      case handle_call(fun, length(args)) do
        {:binary_op, op} ->
          [left, right] = args
          [op_to_binary(left, sources, query), op | op_to_binary(right, sources, query)]

        {:fun, fun} ->
          [
            fun,
            ?(,
            modifier,
            Enum.map_intersperse(args, ", ", &expr(&1, sources, query)),
            ?)
          ]
      end
    end

    defp expr(list, _sources, query) when is_list(list) do
      error!(query, "Array type is not supported by MySQL")
    end

    defp expr(%Decimal{} = decimal, _sources, _query) do
      Decimal.to_string(decimal, :normal)
    end

    defp expr(%Ecto.Query.Tagged{value: binary, type: :binary}, _sources, _query)
         when is_binary(binary) do
      hex = Base.encode16(binary, case: :lower)
      [?x, ?', hex, ?']
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query)
         when type in [:decimal, :float] do
      [expr(other, sources, query), " + 0"]
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: :boolean}, sources, query) do
      ["IF(", expr(other, sources, query), ", TRUE, FALSE)"]
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query) do
      ["CAST(", expr(other, sources, query), " AS ", ecto_cast_to_db(type, query), ?)]
    end

    defp expr(nil, _sources, _query), do: "NULL"
    defp expr(true, _sources, _query), do: "TRUE"
    defp expr(false, _sources, _query), do: "FALSE"

    defp expr(literal, _sources, _query) when is_binary(literal) do
      [?', escape_string(literal), ?']
    end

    defp expr(literal, _sources, _query) when is_integer(literal) do
      Integer.to_string(literal)
    end

    defp expr(literal, _sources, _query) when is_float(literal) do
      # MySQL doesn't support float cast
      ["(0 + ", Float.to_string(literal), ?)]
    end

    defp expr(expr, _sources, query) do
      error!(query, "unsupported expression: #{inspect(expr)}")
    end

    defp values_list(types, num_rows, query) do
      rows = :lists.seq(1, num_rows, 1)

      [
        "VALUES ",
        Enum.map_intersperse(rows, ?,, fn _ ->
          ["ROW(", values_expr(types, query), ?)]
        end)
      ]
    end

    defp values_expr(types, query) do
      Enum.map_intersperse(types, ?,, fn {_field, type} ->
        ["CAST(", ??, " AS ", ecto_cast_to_db(type, query), ?)]
      end)
    end

    defp interval(count, "millisecond", sources, query) do
      ["INTERVAL (", expr(count, sources, query) | " * 1000) microsecond"]
    end

    defp interval(count, interval, sources, query) do
      ["INTERVAL ", expr(count, sources, query), ?\s | interval]
    end

    defp op_to_binary({op, _, [_, _]} = expr, sources, query) when op in @binary_ops,
      do: paren_expr(expr, sources, query)

    defp op_to_binary({:is_nil, _, [_]} = expr, sources, query),
      do: paren_expr(expr, sources, query)

    defp op_to_binary(expr, sources, query),
      do: expr(expr, sources, query)

    defp create_names(%{sources: sources}, as_prefix) do
      create_names(sources, 0, tuple_size(sources), as_prefix) |> List.to_tuple()
    end

    defp create_names(sources, pos, limit, as_prefix) when pos < limit do
      [create_name(sources, pos, as_prefix) | create_names(sources, pos + 1, limit, as_prefix)]
    end

    defp create_names(_sources, pos, pos, as_prefix) do
      [as_prefix]
    end

    defp subquery_as_prefix(sources) do
      [?s | :erlang.element(tuple_size(sources), sources)]
    end

    defp create_name(sources, pos, as_prefix) do
      case elem(sources, pos) do
        {:fragment, _, _} ->
          {nil, as_prefix ++ [?f | Integer.to_string(pos)], nil}

        {:values, _, _} ->
          {nil, as_prefix ++ [?v | Integer.to_string(pos)], nil}

        {table, schema, prefix} ->
          name = as_prefix ++ [create_alias(table) | Integer.to_string(pos)]
          {quote_table(prefix, table), name, schema}

        %Ecto.SubQuery{} ->
          {nil, as_prefix ++ [?s | Integer.to_string(pos)], nil}
      end
    end

    defp create_alias(<<first, _rest::binary>>) when first in ?a..?z when first in ?A..?Z do
      first
    end

    defp create_alias(_) do
      ?t
    end

    ## DDL

    alias Ecto.Migration.{Table, Index, Reference, Constraint}

    @impl true
    def execute_ddl({command, %Table{} = table, columns})
        when command in [:create, :create_if_not_exists] do
      table_structure =
        case column_definitions(table, columns) ++ pk_definitions(columns, ", ") do
          [] -> []
          list -> [?\s, ?(, list, ?)]
        end

      [
        [
          "CREATE TABLE ",
          if_do(command == :create_if_not_exists, "IF NOT EXISTS "),
          quote_table(table.prefix, table.name),
          table_structure,
          comment_expr(table.comment, true),
          engine_expr(table.engine),
          options_expr(table.options)
        ]
      ]
    end

    def execute_ddl({command, %Table{} = table, mode}) when command in [:drop, :drop_if_exists] do
      [
        [
          "DROP TABLE ",
          if_do(command == :drop_if_exists, "IF EXISTS "),
          quote_table(table.prefix, table.name),
          drop_mode(mode)
        ]
      ]
    end

    def execute_ddl({:alter, %Table{} = table, changes}) do
      [
        [
          "ALTER TABLE ",
          quote_table(table.prefix, table.name),
          ?\s,
          column_changes(table, changes),
          pk_definitions(changes, ", ADD ")
        ]
      ] ++
        if_do(
          table.comment,
          [["ALTER TABLE ", quote_table(table.prefix, table.name), comment_expr(table.comment)]]
        )
    end

    def execute_ddl({:create, %Index{} = index}) do
      if index.where do
        error!(nil, "MySQL adapter does not support where in indexes")
      end

      if index.nulls_distinct == false do
        error!(nil, "MySQL adapter does not support nulls_distinct set to false in indexes")
      end

      [
        [
          "CREATE",
          if_do(index.unique, " UNIQUE"),
          " INDEX ",
          quote_name(index.name),
          " ON ",
          quote_table(index.prefix, index.table),
          ?\s,
          ?(,
          Enum.map_intersperse(index.columns, ", ", &index_expr/1),
          ?),
          if_do(index.using, [" USING ", to_string(index.using)]),
          if_do(index.concurrently, " LOCK=NONE")
        ]
      ]
    end

    def execute_ddl({:create_if_not_exists, %Index{}}),
      do: error!(nil, "MySQL adapter does not support create if not exists for index")

    def execute_ddl({:create, %Constraint{check: check} = constraint}) when is_binary(check) do
      table_name = quote_name(constraint.prefix, constraint.table)
      [["ALTER TABLE ", table_name, " ADD ", new_constraint_expr(constraint)]]
    end

    def execute_ddl({:create, %Constraint{exclude: exclude}}) when is_binary(exclude),
      do: error!(nil, "MySQL adapter does not support exclusion constraints")

    def execute_ddl({:drop, %Constraint{}, :cascade}),
      do: error!(nil, "MySQL does not support `CASCADE` in `DROP CONSTRAINT` commands")

    def execute_ddl({:drop, %Constraint{} = constraint, _}) do
      [
        [
          "ALTER TABLE ",
          quote_name(constraint.prefix, constraint.table),
          " DROP CONSTRAINT ",
          quote_name(constraint.name)
        ]
      ]
    end

    def execute_ddl({:drop_if_exists, %Constraint{}, _}),
      do: error!(nil, "MySQL adapter does not support `drop_if_exists` for constraints")

    def execute_ddl({:drop, %Index{}, :cascade}),
      do: error!(nil, "MySQL adapter does not support cascade in drop index")

    def execute_ddl({:drop, %Index{} = index, :restrict}) do
      [
        [
          "DROP INDEX ",
          quote_name(index.name),
          " ON ",
          quote_table(index.prefix, index.table),
          if_do(index.concurrently, " LOCK=NONE")
        ]
      ]
    end

    def execute_ddl({:drop_if_exists, %Index{}, _}),
      do: error!(nil, "MySQL adapter does not support drop if exists for index")

    def execute_ddl({:rename, %Index{} = index, new_name}) do
      [
        [
          "ALTER TABLE ",
          quote_table(index.table),
          " RENAME INDEX ",
          quote_name(index.name),
          " TO ",
          quote_name(new_name)
        ]
      ]
    end

    def execute_ddl({:rename, %Table{} = current_table, %Table{} = new_table}) do
      [
        [
          "RENAME TABLE ",
          quote_table(current_table.prefix, current_table.name),
          " TO ",
          quote_table(new_table.prefix, new_table.name)
        ]
      ]
    end

    def execute_ddl({:rename, %Table{} = table, current_column, new_column}) do
      [
        [
          "ALTER TABLE ",
          quote_table(table.prefix, table.name),
          " RENAME COLUMN ",
          quote_name(current_column),
          " TO ",
          quote_name(new_column)
        ]
      ]
    end

    def execute_ddl(string) when is_binary(string), do: [string]

    def execute_ddl(keyword) when is_list(keyword),
      do: error!(nil, "MySQL adapter does not support keyword lists in execute")

    @impl true
    def ddl_logs(_), do: []

    @impl true
    def table_exists_query(table) do
      {"SELECT true FROM information_schema.tables WHERE table_name = ? AND table_schema = DATABASE() LIMIT 1",
       [table]}
    end

    defp drop_mode(:cascade), do: " CASCADE"
    defp drop_mode(:restrict), do: []

    defp pk_definitions(columns, prefix) do
      pks =
        for {action, name, _, opts} <- columns,
            action != :remove,
            opts[:primary_key],
            do: name

      case pks do
        [] -> []
        _ -> [[prefix, "PRIMARY KEY (", quote_names(pks), ?)]]
      end
    end

    defp column_definitions(table, columns) do
      Enum.map_intersperse(columns, ", ", &column_definition(table, &1))
    end

    defp column_definition(table, {:add, name, %Reference{} = ref, opts}) do
      [
        quote_name(name),
        ?\s,
        reference_column_type(ref.type, opts),
        column_options(opts),
        reference_expr(ref, table, name)
      ]
    end

    defp column_definition(_table, {:add, name, type, opts}) do
      [quote_name(name), ?\s, column_type(type, opts), column_options(opts)]
    end

    defp column_changes(table, columns) do
      Enum.map_intersperse(columns, ", ", &column_change(table, &1))
    end

    defp column_change(_table, {_command, _name, %Reference{validate: false}, _opts}) do
      error!(nil, "validate: false on references is not supported in MyXQL")
    end

    defp column_change(table, {:add, name, %Reference{} = ref, opts}) do
      [
        "ADD ",
        quote_name(name),
        ?\s,
        reference_column_type(ref.type, opts),
        column_options(opts),
        constraint_expr(ref, table, name)
      ]
    end

    defp column_change(_table, {:add, name, type, opts}) do
      ["ADD ", quote_name(name), ?\s, column_type(type, opts), column_options(opts)]
    end

    defp column_change(table, {:add_if_not_exists, name, %Reference{} = ref, opts}) do
      [
        "ADD IF NOT EXISTS ",
        quote_name(name),
        ?\s,
        reference_column_type(ref.type, opts),
        column_options(opts),
        constraint_if_not_exists_expr(ref, table, name)
      ]
    end

    defp column_change(_table, {:add_if_not_exists, name, type, opts}) do
      [
        "ADD IF NOT EXISTS ",
        quote_name(name),
        ?\s,
        column_type(type, opts),
        column_options(opts)
      ]
    end

    defp column_change(table, {:modify, name, %Reference{} = ref, opts}) do
      [
        drop_constraint_expr(opts[:from], table, name),
        "MODIFY ",
        quote_name(name),
        ?\s,
        reference_column_type(ref.type, opts),
        column_options(opts),
        constraint_expr(ref, table, name)
      ]
    end

    defp column_change(table, {:modify, name, type, opts}) do
      [
        drop_constraint_expr(opts[:from], table, name),
        "MODIFY ",
        quote_name(name),
        ?\s,
        column_type(type, opts),
        column_options(opts)
      ]
    end

    defp column_change(_table, {:remove, name}), do: ["DROP ", quote_name(name)]

    defp column_change(table, {:remove, name, %Reference{} = ref, _opts}) do
      [drop_constraint_expr(ref, table, name), "DROP ", quote_name(name)]
    end

    defp column_change(_table, {:remove, name, _type, _opts}), do: ["DROP ", quote_name(name)]

    defp column_change(table, {:remove_if_exists, name, %Reference{} = ref}) do
      [drop_constraint_if_exists_expr(ref, table, name), "DROP IF EXISTS ", quote_name(name)]
    end

    defp column_change(table, {:remove_if_exists, name, _type}),
      do: column_change(table, {:remove_if_exists, name})

    defp column_change(_table, {:remove_if_exists, name}),
      do: ["DROP IF EXISTS ", quote_name(name)]

    defp column_options(opts) do
      default = Keyword.fetch(opts, :default)
      null = Keyword.get(opts, :null)
      after_column = Keyword.get(opts, :after)
      comment = Keyword.get(opts, :comment)
      collation = Keyword.fetch(opts, :collation)

      [
        default_expr(default),
        collation_expr(collation),
        null_expr(null),
        comment_expr(comment),
        after_expr(after_column)
      ]
    end

    defp comment_expr(comment, create_table? \\ false)

    defp comment_expr(comment, true) when is_binary(comment),
      do: " COMMENT = '#{escape_string(comment)}'"

    defp comment_expr(comment, false) when is_binary(comment),
      do: " COMMENT '#{escape_string(comment)}'"

    defp comment_expr(_, _), do: []

    defp after_expr(nil), do: []
    defp after_expr(column) when is_atom(column) or is_binary(column), do: " AFTER `#{column}`"
    defp after_expr(_), do: []

    defp null_expr(false), do: " NOT NULL"
    defp null_expr(true), do: " NULL"
    defp null_expr(_), do: []

    defp collation_expr({:ok, collation_name}), do: " COLLATE \"#{collation_name}\""
    defp collation_expr(_), do: []

    defp new_constraint_expr(%Constraint{check: check} = constraint) when is_binary(check) do
      [
        "CONSTRAINT ",
        quote_name(constraint.name),
        " CHECK (",
        check,
        ")",
        validate(constraint.validate)
      ]
    end

    defp default_expr({:ok, nil}),
      do: " DEFAULT NULL"

    defp default_expr({:ok, literal}) when is_binary(literal),
      do: [" DEFAULT '", escape_string(literal), ?']

    defp default_expr({:ok, literal}) when is_number(literal) or is_boolean(literal),
      do: [" DEFAULT ", to_string(literal)]

    defp default_expr({:ok, {:fragment, expr}}),
      do: [" DEFAULT ", expr]

    defp default_expr({:ok, value}) when is_map(value) do
      library = Application.get_env(:myxql, :json_library, Jason)
      expr = IO.iodata_to_binary(library.encode_to_iodata!(value))
      [" DEFAULT ", ?(, ?', escape_string(expr), ?', ?)]
    end

    defp default_expr(:error),
      do: []

    defp index_expr({dir, literal})
         when is_binary(literal),
         do: index_dir(dir, literal)

    defp index_expr({dir, literal}),
      do: index_dir(dir, quote_name(literal))

    defp index_expr(literal) when is_binary(literal),
      do: literal

    defp index_expr(literal), do: quote_name(literal)

    defp index_dir(dir, str)
         when dir in [
                :asc,
                :asc_nulls_first,
                :asc_nulls_last,
                :desc,
                :desc_nulls_first,
                :desc_nulls_last
              ] do
      case dir do
        :asc -> [str | " ASC"]
        :desc -> [str | " DESC"]
        _ -> error!(nil, "#{dir} is not supported in indexes in MySQL")
      end
    end

    defp engine_expr(storage_engine),
      do: [" ENGINE = ", String.upcase(to_string(storage_engine || "INNODB"))]

    defp options_expr(nil),
      do: []

    defp options_expr(keyword) when is_list(keyword),
      do: error!(nil, "MySQL adapter does not support keyword lists in :options")

    defp options_expr(options),
      do: [?\s, to_string(options)]

    defp column_type(type, opts) when type in ~w(time utc_datetime naive_datetime)a do
      generated = Keyword.get(opts, :generated)
      [ecto_to_db(type), generated_expr(generated)]
    end

    defp column_type(type, opts)
         when type in ~w(time_usec utc_datetime_usec naive_datetime_usec)a do
      precision = Keyword.get(opts, :precision, 6)
      generated = Keyword.get(opts, :generated)
      type_name = ecto_to_db(type)

      [type_name, ?(, to_string(precision), ?), generated_expr(generated)]
    end

    defp column_type(type, opts) do
      size = Keyword.get(opts, :size)
      precision = Keyword.get(opts, :precision)
      generated = Keyword.get(opts, :generated)
      scale = Keyword.get(opts, :scale)

      type =
        cond do
          size -> [ecto_size_to_db(type), ?(, to_string(size), ?)]
          precision -> [ecto_to_db(type), ?(, to_string(precision), ?,, to_string(scale || 0), ?)]
          type == :string -> ["varchar(255)"]
          true -> ecto_to_db(type)
        end

      [type, generated_expr(generated)]
    end

    defp generated_expr(nil), do: []

    defp generated_expr(expr) when is_binary(expr) do
      [" AS ", expr]
    end

    defp generated_expr(other) do
      raise ArgumentError,
            "the `:generated` option only accepts strings, received: #{inspect(other)}"
    end

    defp reference_expr(type, ref, table, name) do
      {current_columns, reference_columns} = Enum.unzip([{name, ref.column} | ref.with])

      if ref.match do
        error!(nil, ":match is not supported in references for tds")
      end

      [
        "CONSTRAINT ",
        reference_name(ref, table, name),
        " ",
        type,
        " (",
        quote_names(current_columns),
        ?),
        " REFERENCES ",
        quote_table(Keyword.get(ref.options, :prefix, table.prefix), ref.table),
        ?(,
        quote_names(reference_columns),
        ?),
        reference_on_delete(ref.on_delete),
        reference_on_update(ref.on_update)
      ]
    end

    defp reference_expr(%Reference{} = ref, table, name),
      do: [", " | reference_expr("FOREIGN KEY", ref, table, name)]

    defp constraint_expr(%Reference{} = ref, table, name),
      do: [", ADD " | reference_expr("FOREIGN KEY", ref, table, name)]

    defp constraint_if_not_exists_expr(%Reference{} = ref, table, name),
      do: [", ADD " | reference_expr("FOREIGN KEY IF NOT EXISTS", ref, table, name)]

    defp drop_constraint_expr({%Reference{} = ref, _opts}, table, name),
      do: drop_constraint_expr(ref, table, name)

    defp drop_constraint_expr(%Reference{} = ref, table, name),
      do: ["DROP FOREIGN KEY ", reference_name(ref, table, name), ", "]

    defp drop_constraint_expr(_, _, _),
      do: []

    defp drop_constraint_if_exists_expr(%Reference{} = ref, table, name),
      do: ["DROP FOREIGN KEY IF EXISTS ", reference_name(ref, table, name), ", "]

    defp drop_constraint_if_exists_expr(_, _, _),
      do: []

    defp reference_name(%Reference{name: nil}, table, column),
      do: quote_name("#{table.name}_#{column}_fkey")

    defp reference_name(%Reference{name: name}, _table, _column),
      do: quote_name(name)

    defp reference_column_type(:serial, _opts), do: "BIGINT UNSIGNED"
    defp reference_column_type(:bigserial, _opts), do: "BIGINT UNSIGNED"
    defp reference_column_type(type, opts), do: column_type(type, opts)

    defp reference_on_delete(:nilify_all), do: " ON DELETE SET NULL"

    defp reference_on_delete({:nilify, _columns}) do
      error!(
        nil,
        "MySQL adapter does not support the `{:nilify, columns}` action for `:on_delete`"
      )
    end

    defp reference_on_delete(:default_all) do
      error!(
        nil,
        "MySQL adapter does not support the `:default_all` action for `:on_delete`"
      )
    end

    defp reference_on_delete({:default, _columns}) do
      error!(
        nil,
        "MySQL adapter does not support the `{:default, columns}` action for `:on_delete`"
      )
    end

    defp reference_on_delete(:delete_all), do: " ON DELETE CASCADE"
    defp reference_on_delete(:restrict), do: " ON DELETE RESTRICT"
    defp reference_on_delete(_), do: []

    defp reference_on_update(:nilify_all), do: " ON UPDATE SET NULL"
    defp reference_on_update(:update_all), do: " ON UPDATE CASCADE"
    defp reference_on_update(:restrict), do: " ON UPDATE RESTRICT"
    defp reference_on_update(_), do: []

    defp validate(false), do: " NOT ENFORCED"
    defp validate(_), do: []

    ## Helpers

    defp get_source(query, sources, ix, source) do
      {expr, name, _schema} = elem(sources, ix)
      name = maybe_add_column_names(source, name)
      {expr || expr(source, sources, query), name}
    end

    defp get_parent_sources_ix(query, as) do
      case query.aliases[@parent_as] do
        {%{aliases: %{^as => ix}}, sources} -> {ix, sources}
        {%{} = parent, _sources} -> get_parent_sources_ix(parent, as)
      end
    end

    defp maybe_add_column_names({:values, _, [types, _, _]}, name) do
      fields = Keyword.keys(types)
      [name, ?\s, ?(, quote_names(fields), ?)]
    end

    defp maybe_add_column_names(_, name), do: name

    defp quote_name(nil, name), do: quote_name(name)

    defp quote_name(prefix, name), do: [quote_name(prefix), ?., quote_name(name)]

    defp quote_name(name) when is_atom(name) do
      quote_name(Atom.to_string(name))
    end

    defp quote_name(name) when is_binary(name) do
      if String.contains?(name, "`") do
        error!(nil, "bad literal/field/table name #{inspect(name)} (` is not permitted)")
      end

      [?`, name, ?`]
    end

    defp quote_names(names), do: Enum.map_intersperse(names, ?,, &quote_name/1)

    defp quote_table(nil, name), do: quote_table(name)
    defp quote_table(prefix, name), do: [quote_table(prefix), ?., quote_table(name)]

    defp quote_table(name) when is_atom(name),
      do: quote_table(Atom.to_string(name))

    defp quote_table(name) do
      if String.contains?(name, "`") do
        error!(nil, "bad table name #{inspect(name)}")
      end

      [?`, name, ?`]
    end

    defp format_to_sql(:map), do: "FORMAT=JSON"
    defp format_to_sql(:text), do: "FORMAT=TRADITIONAL"

    defp if_do(condition, value) do
      if condition, do: value, else: []
    end

    defp escape_string(value) when is_binary(value) do
      value
      |> :binary.replace("'", "''", [:global])
      |> :binary.replace("\\", "\\\\", [:global])
    end

    defp escape_json_key(value) when is_binary(value) do
      value
      |> escape_string()
      |> :binary.replace("\"", "\\\\\"", [:global])
    end

    defp ecto_cast_to_db(:id, _query), do: "unsigned"
    defp ecto_cast_to_db(:integer, _query), do: "signed"
    defp ecto_cast_to_db(:string, _query), do: "char"
    defp ecto_cast_to_db(:utc_datetime_usec, _query), do: "datetime(6)"
    defp ecto_cast_to_db(:naive_datetime_usec, _query), do: "datetime(6)"
    defp ecto_cast_to_db(type, query), do: ecto_to_db(type, query)

    defp ecto_size_to_db(:binary), do: "varbinary"
    defp ecto_size_to_db(type), do: ecto_to_db(type)

    defp ecto_to_db(type, query \\ nil)
    defp ecto_to_db({:array, _}, query), do: error!(query, "Array type is not supported by MySQL")
    defp ecto_to_db(:id, _query), do: "integer"
    defp ecto_to_db(:serial, _query), do: "bigint unsigned not null auto_increment"
    defp ecto_to_db(:bigserial, _query), do: "bigint unsigned not null auto_increment"
    defp ecto_to_db(:binary_id, _query), do: "binary(16)"
    defp ecto_to_db(:string, _query), do: "varchar"
    defp ecto_to_db(:float, _query), do: "double"
    defp ecto_to_db(:binary, _query), do: "blob"
    # MySQL does not support uuid
    defp ecto_to_db(:uuid, _query), do: "binary(16)"
    defp ecto_to_db(:map, _query), do: "json"
    defp ecto_to_db({:map, _}, _query), do: "json"
    defp ecto_to_db(:time_usec, _query), do: "time"
    defp ecto_to_db(:utc_datetime, _query), do: "datetime"
    defp ecto_to_db(:utc_datetime_usec, _query), do: "datetime"
    defp ecto_to_db(:naive_datetime, _query), do: "datetime"
    defp ecto_to_db(:naive_datetime_usec, _query), do: "datetime"
    defp ecto_to_db(atom, _query) when is_atom(atom), do: Atom.to_string(atom)

    defp ecto_to_db(type, _query) do
      raise ArgumentError,
            "unsupported type `#{inspect(type)}`. The type can either be an atom, a string " <>
              "or a tuple of the form `{:map, t}` where `t` itself follows the same conditions."
    end

    defp error!(nil, message) do
      raise ArgumentError, message
    end

    defp error!(query, message) do
      raise Ecto.QueryError, query: query, message: message
    end
  end
end
