if Code.ensure_loaded?(Tds) do
  defmodule Ecto.Adapters.Tds.Connection do
    @moduledoc false
    require Logger
    alias Tds.Query
    alias Ecto.Query.Tagged
    alias Ecto.Adapters.SQL
    require Ecto.Schema

    @behaviour Ecto.Adapters.SQL.Connection

    @impl true
    def child_spec(opts) do
      opts
      |> Keyword.put_new(:use_elixir_calendar_types, true)
      |> Tds.child_spec()
    end

    @impl true
    def prepare_execute(pid, _name, statement, params, opts \\ []) do
      query = %Query{statement: statement}
      params = prepare_params(params)

      opts = Keyword.put(opts, :parameters, params)
      DBConnection.prepare_execute(pid, query, params, opts)
    end

    @impl true
    def execute(pid, statement, params, opts) when is_binary(statement) or is_list(statement) do
      query = %Query{statement: statement}
      params = prepare_params(params)
      opts = Keyword.put(opts, :parameters, params)

      case DBConnection.prepare_execute(pid, query, params, opts) do
        {:ok, _, %Tds.Result{columns: nil, num_rows: num_rows, rows: []}}
        when num_rows >= 0 ->
          {:ok, %Tds.Result{columns: nil, num_rows: num_rows, rows: nil}}

        {:ok, _, query} ->
          {:ok, query}

        {:error, _} = err ->
          err
      end
    end

    def execute(pid, %{} = query, params, opts) do
      opts = Keyword.put_new(opts, :parameters, params)
      params = prepare_params(params)
      opts = Keyword.put(opts, :parameters, params)

      case DBConnection.prepare_execute(pid, query, params, opts) do
        {:ok, _, query} -> {:ok, query}
        {:error, _} = err -> err
      end
    end

    @impl true
    def stream(_conn, _sql, _params, _opts) do
      error!(nil, "Repo.stream is not supported in the Tds adapter")
    end

    @impl true
    def query(conn, sql, params, opts) do
      params = prepare_params(params)
      Tds.query(conn, sql, params, opts)
    end

    @impl true
    def query_many(_conn, _sql, _params, _opts) do
      error!(nil, "query_many is not supported in the Tds adapter")
    end

    @impl true
    def to_constraints(%Tds.Error{mssql: %{number: code, msg_text: message}}, _opts) do
      Tds.Error.get_constraint_violations(code, message)
    end

    def to_constraints(_, _opts), do: []

    def prepare_params(params) do
      unless is_list(params) do
        raise ArgumentError, "expected params to be a list, got: #{inspect(params)}"
      end

      {params, _} =
        Enum.map_reduce(params, 1, fn param, acc ->
          case prepare_param(param) do
            {value, type} -> {%Tds.Parameter{name: "@#{acc}", value: value, type: type}, acc + 1}
            %Tds.Parameter{name: ""} = param -> {%{param | name: "@#{acc}"}, acc + 1}
            %Tds.Parameter{name: <<"@", _::binary>>} = param -> {param, acc}
            _ -> error!(nil, "Tds parameter names must begin with @")
          end
        end)

      params
    end

    # Decimal
    defp prepare_param(%Decimal{} = value) do
      {value, :decimal}
    end

    defp prepare_param(%NaiveDateTime{} = value) do
      {value, :datetime2}
    end

    defp prepare_param(%DateTime{} = value) do
      {value, :datetimeoffset}
    end

    defp prepare_param(%Date{} = value) do
      {value, :date}
    end

    defp prepare_param(%Time{} = value) do
      {value, :time}
    end

    defp prepare_param(%Tds.Parameter{type: nil, value: value} = param) do
      {_value, type} = prepare_param(value)
      %{param | type: type}
    end

    defp prepare_param(%Tds.Parameter{} = param) do
      param
    end

    defp prepare_param(%{__struct__: module} = _value) do
      # just in case dumpers/loaders are not defined for the this struct
      error!(
        nil,
        "Tds adapter is unable to convert struct `#{inspect(module)}` into supported MSSQL types"
      )
    end

    defp prepare_param(%{} = value), do: {json_library().encode!(value), :string}
    defp prepare_param(value), do: prepare_raw_param(value)

    defp prepare_raw_param(value) when is_binary(value) do
      type = if String.printable?(value), do: :string, else: :binary
      {value, type}
    end

    defp prepare_raw_param(value) when value == true, do: {1, :boolean}
    defp prepare_raw_param(value) when value == false, do: {0, :boolean}
    defp prepare_raw_param({_, :varchar} = value), do: value
    defp prepare_raw_param(value), do: {value, nil}

    defp json_library(), do: Application.get_env(:tds, :json_library, Jason)

    ## Query

    @parent_as __MODULE__
    alias Ecto.Query
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
      _window = window(query, sources)
      combinations = combinations(query, as_prefix)
      order_by = order_by(query, sources)
      # limit = is handled in select (TOP X)
      offset = offset(query, sources)
      lock = lock(query, sources)

      if query.offset != nil and query.order_bys == [],
        do: error!(query, "ORDER BY is mandatory when OFFSET is set")

      [cte, select, from, join, where, group_by, having, combinations, order_by, lock | offset]
    end

    @impl true
    def update_all(query) do
      sources = create_names(query, [])
      cte = cte(query, sources)
      {table, name, _model} = elem(sources, 0)

      fields = update_fields(query, sources)
      from = " FROM #{table} AS #{name}"
      join = join(query, sources)
      where = where(query, sources)
      lock = lock(query, sources)

      [
        cte,
        "UPDATE ",
        name,
        " SET ",
        fields,
        returning(query, 0, "INSERTED"),
        from,
        join,
        where | lock
      ]
    end

    @impl true
    def delete_all(query) do
      sources = create_names(query, [])
      cte = cte(query, sources)
      {table, name, _model} = elem(sources, 0)

      delete = "DELETE #{name}"
      from = " FROM #{table} AS #{name}"
      join = join(query, sources)
      where = where(query, sources)
      lock = lock(query, sources)

      [cte, delete, returning(query, 0, "DELETED"), from, join, where | lock]
    end

    @impl true
    def insert(prefix, table, header, rows, on_conflict, returning, placeholders) do
      counter_offset = length(placeholders) + 1
      [] = on_conflict(on_conflict, header)
      returning = returning(returning, "INSERTED")

      values =
        if header == [] do
          [returning, " DEFAULT VALUES"]
        else
          [
            ?\s,
            ?(,
            quote_names(header),
            ?),
            returning
            | insert_all(rows, counter_offset)
          ]
        end

      ["INSERT INTO ", quote_table(prefix, table), values]
    end

    defp on_conflict({:raise, _, []}, _header) do
      []
    end

    defp on_conflict({_, _, _}, _header) do
      error!(nil, "Tds adapter supports only on_conflict: :raise")
    end

    defp insert_all(%Ecto.Query{} = query, _counter) do
      [?\s, all(query)]
    end

    defp insert_all(rows, counter) do
      sql =
        intersperse_reduce(rows, ",", counter, fn row, counter ->
          {row, counter} = insert_each(row, counter)
          {[?(, row, ?)], counter}
        end)
        |> elem(0)

      [" VALUES " | sql]
    end

    defp insert_each(values, counter) do
      intersperse_reduce(values, ", ", counter, fn
        nil, counter ->
          {"DEFAULT", counter}

        {%Query{} = query, params_counter}, counter ->
          {[?(, all(query), ?)], counter + params_counter}

        {:placeholder, placeholder_index}, counter ->
          {[?@ | placeholder_index], counter}

        _, counter ->
          {[?@ | Integer.to_string(counter)], counter + 1}
      end)
    end

    @impl true
    def update(prefix, table, fields, filters, returning) do
      {fields, count} =
        intersperse_reduce(fields, ", ", 1, fn field, acc ->
          {[quote_name(field), " = @", Integer.to_string(acc)], acc + 1}
        end)

      {filters, _count} =
        intersperse_reduce(filters, " AND ", count, fn
          {field, nil}, acc ->
            {[quote_name(field), " IS NULL"], acc + 1}

          {field, _value}, acc ->
            {[quote_name(field), " = @", Integer.to_string(acc)], acc + 1}

          field, acc ->
            {[quote_name(field), " = @", Integer.to_string(acc)], acc + 1}
        end)

      [
        "UPDATE ",
        quote_table(prefix, table),
        " SET ",
        fields,
        returning(returning, "INSERTED"),
        " WHERE " | filters
      ]
    end

    @impl true
    def delete(prefix, table, filters, returning) do
      {filters, _} =
        intersperse_reduce(filters, " AND ", 1, fn
          {field, nil}, acc ->
            {[quote_name(field), " IS NULL"], acc + 1}

          {field, _value}, acc ->
            {[quote_name(field), " = @", Integer.to_string(acc)], acc + 1}

          field, acc ->
            {[quote_name(field), " = @", Integer.to_string(acc)], acc + 1}
        end)

      [
        "DELETE FROM ",
        quote_table(prefix, table),
        returning(returning, "DELETED"),
        " WHERE " | filters
      ]
    end

    @impl true
    def explain_query(conn, query, params, opts) do
      params = prepare_params(params)

      case Tds.query_multi(conn, build_explain_query(query), params, opts) do
        {:ok, [_, %Tds.Result{} = result, _]} ->
          {:ok, SQL.format_table(result)}

        error ->
          error
      end
    end

    def build_explain_query(query) do
      [
        "SET STATISTICS XML ON; ",
        "SET STATISTICS PROFILE ON; ",
        query,
        "; ",
        "SET STATISTICS XML OFF; ",
        "SET STATISTICS PROFILE OFF;"
      ]
      |> IO.iodata_to_binary()
    end

    ## Query generation

    binary_ops = [
      ==: " = ",
      !=: " <> ",
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
      ilike: " LIKE ",
      like: " LIKE "
    ]

    @binary_ops Keyword.keys(binary_ops)

    Enum.map(binary_ops, fn {op, str} ->
      defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
    end)

    defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

    defp select(%{select: %{fields: fields}, distinct: distinct} = query, sources) do
      [
        "SELECT ",
        distinct(distinct, sources, query),
        limit(query, sources),
        select(fields, sources, query)
      ]
    end

    defp distinct(nil, _sources, _query), do: []
    defp distinct(%ByExpr{expr: true}, _sources, _query), do: "DISTINCT "
    defp distinct(%ByExpr{expr: false}, _sources, _query), do: []

    defp distinct(%ByExpr{expr: exprs}, _sources, query) when is_list(exprs) do
      error!(
        query,
        "DISTINCT with multiple columns is not supported by MsSQL. " <>
          "Please use distinct(true) if you need distinct resultset"
      )
    end

    defp select([], _sources, _query) do
      "CAST(1 as bit)"
    end

    defp select(fields, sources, query) do
      Enum.map_intersperse(fields, ", ", fn
        {:&, _, [idx]} ->
          case elem(sources, idx) do
            {nil, source, nil} ->
              error!(
                query,
                "Tds adapter does not support selecting all fields from fragment #{source}. " <>
                  "Please specify exactly which fields you want to select"
              )

            {source, _, nil} ->
              error!(
                query,
                "Tds adapter does not support selecting all fields from #{source} without a schema. " <>
                  "Please specify a schema or specify exactly which fields you want in projection"
              )

            {_, source, _} ->
              source
          end

        {key, value} ->
          [select_expr(value, sources, query), " AS ", quote_name(key)]

        value ->
          select_expr(value, sources, query)
      end)
    end

    defp select_expr({:not, _, [expr]}, sources, query) do
      [?~, ?(, select_expr(expr, sources, query), ?)]
    end

    defp select_expr(value, sources, query), do: expr(value, sources, query)

    defp from(%{from: %{source: source, hints: hints}} = query, sources) do
      {from, name} = get_source(query, sources, 0, source)

      [" FROM ", from, " AS ", name, hints(hints)]
    end

    defp cte(%{with_ctes: %WithExpr{queries: [_ | _] = queries}} = query, sources) do
      ctes = Enum.map_intersperse(queries, ", ", &cte_expr(&1, sources, query))
      ["WITH ", ctes, " "]
    end

    defp cte(%{with_ctes: _}, _), do: []

    defp cte_expr({_name, %{materialized: materialized}, _cte}, _sources, query)
         when is_boolean(materialized) do
      error!(query, "Tds adapter does not support materialized CTEs")
    end

    defp cte_expr({name, opts, cte}, sources, query) do
      operation_opt = Map.get(opts, :operation)

      [
        quote_name(name),
        cte_header(cte, query),
        " AS ",
        cte_query(cte, sources, query, operation_opt)
      ]
    end

    defp cte_header(%QueryExpr{}, query) do
      error!(
        query,
        "Tds adapter does not support fragment in CTE"
      )
    end

    defp cte_header(%Ecto.Query{select: %{fields: fields}} = query, _) do
      [
        " (",
        Enum.map_intersperse(fields, ",", fn
          {key, _} ->
            quote_name(key)

          other ->
            error!(
              query,
              "Tds adapter expected field name or alias in CTE header," <>
                " instead got #{inspect(other)}"
            )
        end),
        ?)
      ]
    end

    defp cte_query(query, sources, parent_query, nil) do
      cte_query(query, sources, parent_query, :all)
    end

    defp cte_query(%Ecto.Query{} = query, sources, parent_query, :all) do
      query = put_in(query.aliases[@parent_as], {parent_query, sources})
      [?(, all(query, subquery_as_prefix(sources)), ?)]
    end

    defp cte_query(%Ecto.Query{} = query, _sources, _parent_query, operation) do
      error!(query, "Tds adapter does not support data-modifying CTEs (operation: #{operation})")
    end

    defp update_fields(%Query{updates: updates} = query, sources) do
      for(
        %{expr: expr} <- updates,
        {op, kw} <- expr,
        {key, value} <- kw,
        do: update_op(op, key, value, sources, query)
      )
      |> Enum.intersperse(", ")
    end

    defp update_op(:set, key, value, sources, query) do
      {_table, name, _model} = elem(sources, 0)
      [name, ?., quote_name(key), " = " | expr(value, sources, query)]
    end

    defp update_op(:inc, key, value, sources, query) do
      {_table, name, _model} = elem(sources, 0)
      quoted = quote_name(key)

      [name, ?., quoted, " = ", name, ?., quoted, " + " | expr(value, sources, query)]
    end

    defp update_op(command, _key, _value, _sources, query) do
      error!(query, "Unknown update operation #{inspect(command)} for TDS")
    end

    defp join(%{joins: []}, _sources), do: []

    defp join(%{joins: joins} = query, sources) do
      [
        ?\s,
        Enum.map_intersperse(joins, ?\s, fn
          %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix, source: source, hints: hints} ->
            {join, name} = get_source(query, sources, ix, source)
            qual_text = join_qual(qual, query)
            join = join || ["(", expr(source, sources, query) | ")"]
            [qual_text, join, " AS ", name, hints(hints) | join_on(qual, expr, sources, query)]
        end)
      ]
    end

    defp join_on(:cross, true, _sources, _query), do: []
    defp join_on(:inner_lateral, true, _sources, _query), do: []
    defp join_on(:left_lateral, true, _sources, _query), do: []
    defp join_on(_qual, true, _sources, _query), do: [" ON 1 = 1"]
    defp join_on(_qual, expr, sources, query), do: [" ON " | expr(expr, sources, query)]

    defp join_qual(:inner, _), do: "INNER JOIN "
    defp join_qual(:left, _), do: "LEFT OUTER JOIN "
    defp join_qual(:right, _), do: "RIGHT OUTER JOIN "
    defp join_qual(:full, _), do: "FULL OUTER JOIN "
    defp join_qual(:cross, _), do: "CROSS JOIN "
    defp join_qual(:inner_lateral, _), do: "CROSS APPLY "
    defp join_qual(:left_lateral, _), do: "OUTER APPLY "

    defp join_qual(qual, query),
      do: error!(query, "join qualifier #{inspect(qual)} is not supported in the Tds adapter")

    defp where(%Query{wheres: wheres} = query, sources) do
      boolean(" WHERE ", wheres, sources, query)
    end

    defp having(%Query{havings: havings} = query, sources) do
      boolean(" HAVING ", havings, sources, query)
    end

    defp window(%{windows: []}, _sources), do: []

    defp window(_query, _sources),
      do: raise(RuntimeError, "Tds adapter does not support window functions")

    defp group_by(%{group_bys: []}, _sources), do: []

    defp group_by(%{group_bys: group_bys} = query, sources) do
      [
        " GROUP BY "
        | Enum.map_intersperse(group_bys, ", ", fn %ByExpr{expr: expr} ->
            Enum.map_intersperse(expr, ", ", &top_level_expr(&1, sources, query))
          end)
      ]
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
        _ -> error!(query, "#{dir} is not supported in ORDER BY in MSSQL")
      end
    end

    defp limit(%Query{limit: nil}, _sources), do: []

    defp limit(%Query{limit: %{with_ties: true}} = query, _sources) do
      error!(query, "Tds adapter does not support the `:with_ties` limit option")
    end

    defp limit(
           %Query{
             limit: %{
               expr: expr
             }
           } = query,
           sources
         ) do
      case Map.get(query, :offset) do
        nil ->
          ["TOP(", expr(expr, sources, query), ") "]

        _ ->
          []
      end
    end

    defp offset(%{offset: nil}, _sources), do: []

    defp offset(%Query{offset: _, limit: nil} = query, _sources) do
      error!(query, "You must provide a limit while using an offset")
    end

    defp offset(%{offset: offset, limit: limit} = query, sources) do
      [
        " OFFSET ",
        expr(offset.expr, sources, query),
        " ROW",
        " FETCH NEXT ",
        expr(limit.expr, sources, query),
        " ROWS ONLY"
      ]
    end

    defp hints([_ | _] = hints), do: [" WITH (", Enum.intersperse(hints, ", "), ?)]
    defp hints([]), do: []

    defp lock(%{lock: nil}, _sources), do: []
    defp lock(%{lock: binary}, _sources) when is_binary(binary), do: [" OPTION (", binary, ?)]
    defp lock(%{lock: expr} = query, sources), do: [" OPTION (", expr(expr, sources, query), ?)]

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

    defp boolean(_name, [], _sources, _query), do: []

    defp boolean(name, [%{expr: expr, op: op} | query_exprs], sources, query) do
      [
        name
        | Enum.reduce(query_exprs, {op, paren_expr(expr, sources, query)}, fn
            %BooleanExpr{expr: expr, op: op}, {op, acc} ->
              {op, [acc, operator_to_boolean(op), paren_expr(expr, sources, query)]}

            %BooleanExpr{expr: expr, op: op}, {_, acc} ->
              {op, [?(, acc, ?), operator_to_boolean(op), paren_expr(expr, sources, query)]}
          end)
          |> elem(1)
      ]
    end

    defp operator_to_boolean(:and), do: " AND "
    defp operator_to_boolean(:or), do: " OR "

    defp parens_for_select([first_expr | _] = expr) do
      if is_binary(first_expr) and String.match?(first_expr, ~r/^\s*select\s/i) do
        [?(, expr, ?)]
      else
        expr
      end
    end

    defp paren_expr(true, _sources, _query) do
      ["(1 = 1)"]
    end

    defp paren_expr(false, _sources, _query) do
      ["(1 = 0)"]
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

    # :^ - represents parameter ix is index number
    defp expr({:^, [], [idx]}, _sources, _query) do
      "@#{idx + 1}"
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
      {_table, source, _schema} = elem(sources, idx)
      source
    end

    defp expr({:&, _, [idx, fields, _counter]}, sources, query) do
      {_table, name, schema} = elem(sources, idx)

      if is_nil(schema) and is_nil(fields) do
        error!(
          query,
          "Tds adapter requires a schema module when using selector #{inspect(name)} but " <>
            "none was given. Please specify schema " <>
            "or specify exactly which fields from #{inspect(name)} you what in projection"
        )
      end

      Enum.map_join(fields, ", ", &"#{name}.#{quote_name(&1)}")
    end

    # example from {:in, [], [1,   {:^, [], [0, 0]}]}
    defp expr({:in, _, [_left, []]}, _sources, _query) do
      "0=1"
    end

    # example from(p in Post, where: p.id in [1,2, ^some_id])
    defp expr({:in, _, [left, right]}, sources, query) when is_list(right) do
      args = Enum.map_join(right, ",", &expr(&1, sources, query))
      [expr(left, sources, query), " IN (", args | ")"]
    end

    # example from(p in Post, where: p.id in [])
    defp expr({:in, _, [_, {:^, _, [_, 0]}]}, _sources, _query), do: "0=1"

    # example from(p in Post, where: p.id in ^some_list)
    # or from(p in Post, where: p.id in ^[])
    defp expr({:in, _, [left, {:^, _, [idx, length]}]}, sources, query) do
      args = list_param_to_args(idx, length)
      [expr(left, sources, query), " IN (", args | ")"]
    end

    defp expr({:in, _, [left, %Ecto.SubQuery{} = subquery]}, sources, query) do
      [expr(left, sources, query), " IN ", expr(subquery, sources, query)]
    end

    defp expr({:in, _, [left, right]}, sources, query) do
      [expr(left, sources, query), " = ANY(", expr(right, sources, query) | ")"]
    end

    defp expr({:is_nil, _, [arg]}, sources, query) do
      "#{expr(arg, sources, query)} IS NULL"
    end

    defp expr({:not, _, [expr]}, sources, query) do
      ["NOT (", expr(expr, sources, query) | ")"]
    end

    defp expr({:filter, _, _}, _sources, query) do
      error!(query, "Tds adapter does not support aggregate filters")
    end

    defp expr(%Ecto.SubQuery{} = subquery, sources, parent_query) do
      [?(, top_level_expr(subquery, sources, parent_query), ?)]
    end

    defp expr({:fragment, _, [kw]}, _sources, query) when is_list(kw) or tuple_size(kw) == 3 do
      error!(query, "Tds adapter does not support keyword or interpolated fragments")
    end

    defp expr({:fragment, _, parts}, sources, query) do
      Enum.map(parts, fn
        {:raw, part} -> part
        {:expr, expr} -> expr(expr, sources, query)
      end)
      |> parens_for_select
    end

    defp expr({:values, _, [types, idx, num_rows]}, _, _query) do
      [?(, values_list(types, idx + 1, num_rows), ?)]
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

    defp expr({:splice, _, [{:^, _, [idx, length]}]}, _sources, _query) do
      list_param_to_args(idx, length)
    end

    defp expr({:selected_as, _, [name]}, _sources, _query) do
      [quote_name(name)]
    end

    defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
      [
        "DATEADD(",
        interval,
        ", ",
        interval_count(count, sources, query),
        ", CAST(",
        expr(datetime, sources, query),
        " AS datetime2(6)))"
      ]
    end

    defp expr({:date_add, _, [date, count, interval]}, sources, query) do
      [
        "CAST(DATEADD(",
        interval,
        ", ",
        interval_count(count, sources, query),
        ", CAST(",
        expr(date, sources, query),
        " AS datetime2(6))" | ") AS date)"
      ]
    end

    defp expr({:count, _, []}, _sources, _query), do: "count(*)"

    defp expr({:json_extract_path, _, _}, _sources, query) do
      error!(
        query,
        "Tds adapter does not support json_extract_path expression" <>
          ", use fragment with JSON_VALUE/JSON_QUERY"
      )
    end

    defp expr({fun, _, args}, sources, query) when is_atom(fun) and is_list(args) do
      {modifier, args} =
        case args do
          [rest, :distinct] -> {"DISTINCT ", [rest]}
          _ -> {"", args}
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
            Enum.map_intersperse(args, ", ", &top_level_expr(&1, sources, query)),
            ?)
          ]
      end
    end

    defp expr(list, sources, query) when is_list(list) do
      Enum.map_join(list, ", ", &expr(&1, sources, query))
    end

    defp expr({string, :varchar}, _sources, _query)
         when is_binary(string) do
      "'#{escape_string(string)}'"
    end

    defp expr(string, _sources, _query) when is_binary(string) do
      "N'#{escape_string(string)}'"
    end

    defp expr(%Decimal{exp: exp} = decimal, _sources, _query) do
      # this should help gaining precision for decimals values embedded in query
      # but this is still not good enough, for instance:
      #
      # from(p in Post, select: type(2.0 + ^"2", p.cost())))
      #
      # Post.cost is :decimal, but we don't know precision and scale since
      # such info is only available in migration files. So query compilation
      # will yield
      #
      # SELECT CAST(CAST(2.0 as decimal(38, 1)) + @1 AS decimal)
      # FROM [posts] AS p0
      #
      # as long as we have CAST(... as DECIMAL) without precision and scale
      # value could be truncated
      [
        "CAST(",
        Decimal.to_string(decimal, :normal),
        " as decimal(38, #{abs(exp)})",
        ?)
      ]
    end

    defp expr(%Tagged{value: binary, type: :binary}, _sources, _query) when is_binary(binary) do
      hex = Base.encode16(binary, case: :lower)
      "0x#{hex}"
    end

    defp expr(%Tagged{value: binary, type: :uuid}, _sources, _query) when is_binary(binary) do
      case binary do
        <<_::64, ?-, _::32, ?-, _::32, ?-, _::32, ?-, _::96>> ->
          {:ok, value} = Tds.Ecto.UUID.dump(binary)
          value

        any ->
          any
      end
    end

    defp expr(%Tagged{value: other, type: type}, sources, query)
         when type in [:varchar, :nvarchar] do
      "CAST(#{expr(other, sources, query)} AS #{column_type(type, [])}(max))"
    end

    defp expr(%Tagged{value: other, type: :integer}, sources, query) do
      "CAST(#{expr(other, sources, query)} AS bigint)"
    end

    defp expr(%Tagged{value: other, type: type}, sources, query) do
      "CAST(#{expr(other, sources, query)} AS #{column_type(type, [])})"
    end

    defp expr(nil, _sources, _query), do: "NULL"
    defp expr(true, _sources, _query), do: "1"
    defp expr(false, _sources, _query), do: "0"

    defp expr(literal, _sources, _query) when is_binary(literal) do
      "'#{escape_string(literal)}'"
    end

    defp expr(literal, _sources, _query) when is_integer(literal) do
      Integer.to_string(literal)
    end

    defp expr(literal, _sources, _query) when is_float(literal) do
      Float.to_string(literal)
    end

    defp expr(field, _sources, query) do
      error!(query, "unsupported MSSQL expressions: `#{inspect(field)}`")
    end

    defp values_list(types, idx, num_rows) do
      rows = :lists.seq(1, num_rows, 1)

      [
        "VALUES ",
        intersperse_reduce(rows, ?,, idx, fn _, idx ->
          {value, idx} = values_expr(types, idx)
          {[?(, value, ?)], idx}
        end)
        |> elem(0)
      ]
    end

    defp values_expr(types, idx) do
      intersperse_reduce(types, ?,, idx, fn {_field, type}, idx ->
        {["CAST(", ?@, Integer.to_string(idx), " AS ", column_type(type, []), ?)], idx + 1}
      end)
    end

    defp op_to_binary({op, _, [_, _]} = expr, sources, query) when op in @binary_ops do
      paren_expr(expr, sources, query)
    end

    defp op_to_binary({:is_nil, _, [_]} = expr, sources, query) do
      paren_expr(expr, sources, query)
    end

    defp op_to_binary(expr, sources, query) do
      expr(expr, sources, query)
    end

    defp interval_count(count, _sources, _query) when is_integer(count) do
      Integer.to_string(count)
    end

    defp interval_count(count, _sources, _query) when is_float(count) do
      :erlang.float_to_binary(count, [:compact, decimals: 16])
    end

    defp interval_count(count, sources, query) do
      expr(count, sources, query)
    end

    defp returning([], _verb), do: []

    defp returning(returning, verb) when is_list(returning) do
      [" OUTPUT ", Enum.map_intersperse(returning, ", ", &[verb, ?., quote_name(&1)])]
    end

    defp returning(%{select: nil}, _, _),
      do: []

    defp returning(%{select: %{fields: fields}} = query, idx, verb),
      do: [
        " OUTPUT "
        | Enum.map_intersperse(fields, ", ", fn
            {{:., _, [{:&, _, [^idx]}, key]}, _, _} -> [verb, ?., quote_name(key)]
            _ -> error!(query, "MSSQL can only return table #{verb} columns")
          end)
      ]

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

        {table, model, prefix} ->
          name = as_prefix ++ [create_alias(table) | Integer.to_string(pos)]
          {quote_table(prefix, table), name, model}

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

    # DDL
    alias Ecto.Migration.{Table, Index, Reference, Constraint}

    @creates [:create, :create_if_not_exists]
    @drops [:drop, :drop_if_exists]

    @impl true
    def execute_ddl({command, %Table{} = table, columns}) when command in @creates do
      prefix = table.prefix

      pk_name =
        if table.prefix,
          do: "#{table.prefix}_#{table.name}",
          else: table.name

      table_structure =
        table
        |> column_definitions(columns)
        |> Kernel.++(pk_definitions(columns, ", CONSTRAINT [#{pk_name}_pkey] "))
        |> case do
          [] -> []
          list -> [" (", list, ?)]
        end

      create_if_not_exists =
        if_table_not_exists(command == :create_if_not_exists, table.name, prefix)

      [
        [
          create_if_not_exists,
          "CREATE TABLE ",
          quote_table(prefix, table.name),
          table_structure,
          engine_expr(table.engine),
          options_expr(table.options),
          "; "
        ]
      ]
    end

    def execute_ddl({command, %Table{}, :cascade}) when command in @drops,
      do: error!(nil, "MSSQL does not support `CASCADE` in DROP TABLE commands")

    def execute_ddl({command, %Table{} = table, :restrict}) when command in @drops do
      prefix = table.prefix

      [
        [
          if_table_exists(command == :drop_if_exists, table.name, prefix),
          "DROP TABLE ",
          quote_table(prefix, table.name),
          "; "
        ]
      ]
    end

    def execute_ddl({:alter, %Table{} = table, changes}) do
      statement_prefix = ["ALTER TABLE ", quote_table(table.prefix, table.name), " "]

      pk_name =
        if table.prefix,
          do: "#{table.prefix}_#{table.name}",
          else: table.name

      pkeys =
        case pk_definitions(changes, " CONSTRAINT [#{pk_name}_pkey] ") do
          [] -> []
          sql -> [statement_prefix, "ADD", sql]
        end

      [
        [
          column_changes(statement_prefix, table, changes),
          pkeys
        ]
      ]
    end

    def execute_ddl({command, %Index{} = index}) when command in @creates do
      prefix = index.prefix

      if index.using do
        error!(nil, "MSSQL does not support `using` in indexes")
      end

      if index.nulls_distinct == true do
        error!(nil, "MSSQL does not support nulls_distinct set to true in indexes")
      end

      with_options =
        if index.concurrently or index.options != nil do
          [
            " WITH",
            ?(,
            if_do(index.concurrently, "ONLINE=ON"),
            if_do(index.concurrently and index.options != nil, ","),
            if_do(index.options != nil, index.options),
            ?)
          ]
        else
          []
        end

      include =
        index.include
        |> List.wrap()
        |> Enum.map_intersperse(", ", &include_expr/1)

      [
        [
          if_index_not_exists(
            command == :create_if_not_exists,
            index.name,
            unquoted_name(prefix, index.table)
          ),
          "CREATE",
          if_do(index.unique, " UNIQUE"),
          " INDEX ",
          quote_name(index.name),
          " ON ",
          quote_table(prefix, index.table),
          " (",
          Enum.map_intersperse(index.columns, ", ", &index_expr/1),
          ?),
          if_do(include != [], [" INCLUDE ", ?(, include, ?)]),
          if_do(index.where, [" WHERE (", index.where, ?)]),
          with_options,
          ?;
        ]
      ]
    end

    def execute_ddl({:create, %Constraint{exclude: exclude}}) when exclude != nil do
      msg =
        "`:exclude` is not supported Tds adapter check constraint parameter, instead " <>
          "set `:check` attribute with negated expression."

      error!(nil, msg)
    end

    def execute_ddl({:create, %Constraint{validate: false}}) do
      error!(nil, "`:validate` is not supported by the Tds adapter")
    end

    def execute_ddl({:create, %Constraint{} = constraint}) do
      table_name = quote_table(constraint.prefix, constraint.table)

      [
        [
          "ALTER TABLE ",
          table_name,
          " ADD CONSTRAINT ",
          quote_name(constraint.name),
          " ",
          "CHECK (",
          constraint.check,
          "); "
        ]
      ]
    end

    def execute_ddl({:rename, %Index{} = current_index, new_name}) do
      [
        [
          "sp_rename ",
          "N'#{current_index.table}.#{current_index.name}', ",
          "N'#{new_name}', ",
          "N'INDEX'"
        ]
      ]
    end

    def execute_ddl({command, %Index{}, :cascade}) when command in @drops,
      do: error!(nil, "MSSQL does not support `CASCADE` in DROP INDEX commands")

    def execute_ddl({command, %Index{} = index, :restrict}) when command in @drops do
      prefix = index.prefix

      [
        [
          if_index_exists(
            command == :drop_if_exists,
            index.name,
            unquoted_name(prefix, index.table)
          ),
          "DROP INDEX ",
          quote_name(index.name),
          " ON ",
          quote_table(prefix, index.table),
          if_do(index.concurrently, " LOCK=NONE"),
          "; "
        ]
      ]
    end

    def execute_ddl({command, %Constraint{}, :cascade}) when command in @drops,
      do: error!(nil, "MSSQL does not support `CASCADE` in DROP CONSTRAINT commands")

    def execute_ddl({command, %Constraint{} = constraint, _}) when command in @drops do
      table_name = quote_table(constraint.prefix, constraint.table)

      [
        [
          if_check_constraint_exists(
            command == :drop_if_exists,
            constraint.name,
            constraint.prefix
          ),
          "ALTER TABLE ",
          table_name,
          " DROP CONSTRAINT ",
          quote_name(constraint.name),
          "; "
        ]
      ]
    end

    def execute_ddl({:rename, %Table{} = current_table, %Table{} = new_table}) do
      [
        [
          "EXEC sp_rename '",
          unquoted_name(current_table.prefix, current_table.name),
          "', '",
          unquoted_name(new_table.prefix, new_table.name),
          "'"
        ]
      ]
    end

    def execute_ddl({:rename, table, current_column, new_column}) do
      [
        [
          "EXEC sp_rename '",
          unquoted_name(table.prefix, table.name, current_column),
          "', '",
          unquoted_name(new_column),
          "', 'COLUMN'"
        ]
      ]
    end

    def execute_ddl(string) when is_binary(string), do: [string]

    def execute_ddl(keyword) when is_list(keyword),
      do: error!(nil, "Tds adapter does not support keyword lists in execute")

    @impl true
    def ddl_logs(_), do: []

    @impl true
    def table_exists_query(table) do
      {"SELECT 1 FROM sys.tables WHERE [name] = @1", [table]}
    end

    defp pk_definitions(columns, prefix) do
      pks =
        for {action, name, _, opts} <- columns,
            action != :remove,
            opts[:primary_key],
            do: name

      case pks do
        [] ->
          []

        _ ->
          [prefix, "PRIMARY KEY CLUSTERED (", quote_names(pks), ?)]
      end
    end

    defp column_definitions(table, columns) do
      Enum.map_intersperse(columns, ", ", &column_definition(table, &1))
    end

    defp column_definition(table, {:add, name, %Reference{} = ref, opts}) do
      [
        quote_name(name),
        " ",
        reference_column_type(ref.type, opts),
        column_options(table, name, opts),
        reference_expr(ref, table, name)
      ]
    end

    defp column_definition(table, {:add, name, type, opts}) do
      [quote_name(name), " ", column_type(type, opts), column_options(table, name, opts)]
    end

    defp column_changes(statement, table, columns) do
      for column <- columns do
        column_change(statement, table, column)
      end
    end

    defp column_change(_, _, {_, _, %Reference{validate: false}, _}) do
      error!(nil, "validate: false on references is not supported in Tds")
    end

    defp column_change(statement_prefix, table, {:add, name, %Reference{} = ref, opts}) do
      [
        [
          statement_prefix,
          "ADD ",
          quote_name(name),
          " ",
          reference_column_type(ref.type, opts),
          column_options(table, name, opts),
          "; "
        ],
        [statement_prefix, "ADD", constraint_expr(ref, table, name), "; "]
      ]
    end

    defp column_change(statement_prefix, table, {:add, name, type, opts}) do
      [
        [
          statement_prefix,
          "ADD ",
          quote_name(name),
          " ",
          column_type(type, opts),
          column_options(table, name, opts),
          "; "
        ]
      ]
    end

    defp column_change(
           statement_prefix,
           %{name: table_name, prefix: prefix} = table,
           {:add_if_not_exists, column_name, type, opts}
         ) do
      [
        [
          if_column_not_exists(prefix, table_name, column_name),
          statement_prefix,
          "ADD ",
          quote_name(column_name),
          " ",
          column_type(type, opts),
          column_options(table, column_name, opts),
          "; "
        ]
      ]
    end

    defp column_change(statement_prefix, table, {:modify, name, %Reference{} = ref, opts}) do
      [
        drop_constraint_from_expr(opts[:from], table, name, statement_prefix),
        maybe_drop_default_expr(statement_prefix, table, name, opts),
        [
          statement_prefix,
          "ALTER COLUMN ",
          quote_name(name),
          " ",
          reference_column_type(ref.type, opts),
          column_options(table, name, opts),
          "; "
        ],
        [statement_prefix, "ADD", constraint_expr(ref, table, name), "; "],
        [column_default_value(statement_prefix, table, name, opts)]
      ]
    end

    defp column_change(statement_prefix, table, {:modify, name, type, opts}) do
      collation = Keyword.fetch(opts, :collation)

      [
        drop_constraint_from_expr(opts[:from], table, name, statement_prefix),
        maybe_drop_default_expr(statement_prefix, table, name, opts),
        [
          statement_prefix,
          "ALTER COLUMN ",
          quote_name(name),
          " ",
          column_type(type, opts),
          null_expr(Keyword.get(opts, :null)),
          collation_expr(collation),
          "; "
        ],
        [column_default_value(statement_prefix, table, name, opts)]
      ]
    end

    defp column_change(statement_prefix, _table, {:remove, name}) do
      [statement_prefix, "DROP COLUMN ", quote_name(name), "; "]
    end

    defp column_change(statement_prefix, _table, {:remove, name, _type, _opts}),
      do: [statement_prefix, "DROP COLUMN ", quote_name(name)]

    defp column_change(statement_prefix, table, {:remove_if_exists, column_name, _}),
      do: column_change(statement_prefix, table, {:remove_if_exists, column_name})

    defp column_change(
           statement_prefix,
           %{name: table, prefix: prefix},
           {:remove_if_exists, column_name}
         ) do
      [
        [
          if_column_exists(prefix, table, column_name),
          statement_prefix,
          "DROP COLUMN ",
          quote_name(column_name),
          "; "
        ]
      ]
    end

    defp column_options(table, name, opts) do
      default = Keyword.fetch(opts, :default)
      null = Keyword.get(opts, :null)
      collation = Keyword.fetch(opts, :collation)

      [null_expr(null), default_expr(table, name, default), collation_expr(collation)]
    end

    defp column_default_value(statement_prefix, table, name, opts) do
      default_expression = default_expr(table, name, Keyword.fetch(opts, :default))

      case default_expression do
        [] -> []
        _ -> [statement_prefix, "ADD", default_expression, " FOR ", quote_name(name), "; "]
      end
    end

    defp null_expr(false), do: [" NOT NULL"]
    defp null_expr(true), do: [" NULL"]
    defp null_expr(_), do: []

    defp collation_expr({:ok, collation_name}), do: " COLLATE #{collation_name}"
    defp collation_expr(_), do: []

    defp default_expr(_table, _name, {:ok, nil}),
      do: []

    defp default_expr(table, name, {:ok, literal}) when is_binary(literal),
      do: [
        " CONSTRAINT ",
        constraint_name("DF", table, name),
        " DEFAULT (N'",
        escape_string(literal),
        "')"
      ]

    defp default_expr(table, name, {:ok, true}),
      do: [" CONSTRAINT ", constraint_name("DF", table, name), " DEFAULT (1)"]

    defp default_expr(table, name, {:ok, false}),
      do: [" CONSTRAINT ", constraint_name("DF", table, name), " DEFAULT (0)"]

    defp default_expr(table, name, {:ok, literal}) when is_number(literal),
      do: [
        " CONSTRAINT ",
        constraint_name("DF", table, name),
        " DEFAULT (",
        to_string(literal),
        ")"
      ]

    defp default_expr(table, name, {:ok, {:fragment, expr}}),
      do: [" CONSTRAINT ", constraint_name("DF", table, name), " DEFAULT (", expr, ")"]

    defp default_expr(_table, _name, :error), do: []

    defp drop_constraint_from_expr({%Reference{} = ref, _opts}, table, name, stm_prefix),
      do: drop_constraint_from_expr(ref, table, name, stm_prefix)

    defp drop_constraint_from_expr(%Reference{} = ref, table, name, stm_prefix) do
      [stm_prefix, "DROP CONSTRAINT ", reference_name(ref, table, name), "; "]
    end

    defp drop_constraint_from_expr(_, _, _, _),
      do: []

    defp maybe_drop_default_expr(statement_prefix, table, name, opts) do
      if Keyword.has_key?(opts, :default) do
        constraint_name = constraint_name("DF", table, name)
        if_exists_drop_constraint(constraint_name, statement_prefix)
      else
        []
      end
    end

    defp constraint_name(type, table, name),
      do: quote_name("#{type}_#{table.prefix}_#{table.name}_#{name}")

    defp index_expr({dir, literal})
         when is_binary(literal),
         do: index_dir(dir, literal)

    defp index_expr({dir, literal}),
      do: index_dir(dir, quote_name(literal))

    defp index_expr(literal) when is_binary(literal), do: literal
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
        _ -> error!(nil, "#{dir} is not supported in indexes in Tds adapter")
      end
    end

    defp include_expr(literal) when is_binary(literal), do: literal
    defp include_expr(literal), do: quote_name(literal)

    defp engine_expr(_storage_engine), do: [""]

    defp options_expr(nil), do: []

    defp options_expr(keyword) when is_list(keyword),
      do: error!(nil, "Tds adapter does not support keyword lists in :options")

    defp options_expr(options), do: [" ", to_string(options)]

    defp column_type(type, opts) do
      size = Keyword.get(opts, :size)
      precision = Keyword.get(opts, :precision)
      scale = Keyword.get(opts, :scale)
      generated = Keyword.get(opts, :generated)
      [ecto_to_db(type, size, precision, scale), generated_expr(generated)]
    end

    defp generated_expr(nil), do: []

    defp generated_expr(expr) when is_binary(expr) do
      [" AS ", expr]
    end

    defp generated_expr(other) do
      raise ArgumentError,
            "the `:generated` option only accepts strings, received: #{inspect(other)}"
    end

    defp constraint_expr(%Reference{} = ref, table, name) do
      {current_columns, reference_columns} = Enum.unzip([{name, ref.column} | ref.with])

      if ref.match do
        error!(nil, ":match is not supported in references for tds")
      end

      [
        " CONSTRAINT ",
        reference_name(ref, table, name),
        " FOREIGN KEY (#{quote_names(current_columns)})",
        " REFERENCES ",
        quote_table(Keyword.get(ref.options, :prefix, table.prefix), ref.table),
        "(#{quote_names(reference_columns)})",
        reference_on_delete(ref.on_delete),
        reference_on_update(ref.on_update)
      ]
    end

    defp reference_expr(%Reference{} = ref, table, name) do
      [",", constraint_expr(ref, table, name)]
    end

    defp reference_name(%Reference{name: nil}, table, column),
      do: quote_name("#{table.name}_#{column}_fkey")

    defp reference_name(%Reference{name: name}, _table, _column), do: quote_name(name)

    defp reference_column_type(:id, _opts), do: "BIGINT"
    defp reference_column_type(:serial, _opts), do: "INT"
    defp reference_column_type(:bigserial, _opts), do: "BIGINT"
    defp reference_column_type(type, opts), do: column_type(type, opts)

    defp reference_on_delete(:nilify_all), do: " ON DELETE SET NULL"

    defp reference_on_delete({:nilify, _columns}) do
      error!(nil, "Tds adapter does not support the `{:nilify, columns}` action for `:on_delete`")
    end

    defp reference_on_delete(:default_all), do: " ON DELETE SET DEFAULT"

    defp reference_on_delete({:default, _columns}) do
      error!(
        nil,
        "Tds adapter does not support the `{:default, columns}` action for `:on_delete`"
      )
    end

    defp reference_on_delete(:delete_all), do: " ON DELETE CASCADE"
    defp reference_on_delete(:nothing), do: " ON DELETE NO ACTION"
    defp reference_on_delete(_), do: []

    defp reference_on_update(:nilify_all), do: " ON UPDATE SET NULL"
    defp reference_on_update(:update_all), do: " ON UPDATE CASCADE"
    defp reference_on_update(:nothing), do: " ON UPDATE NO ACTION"
    defp reference_on_update(_), do: []

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

    defp quote_name(name) when is_atom(name) do
      quote_name(Atom.to_string(name))
    end

    defp quote_name(name) when is_binary(name) do
      if String.contains?(name, ["[", "]"]) do
        error!(
          nil,
          "bad literal/field/table name #{inspect(name)} ('[' and ']' are not permitted)"
        )
      end

      "[#{name}]"
    end

    defp quote_names(names), do: Enum.map_intersperse(names, ?,, &quote_name/1)

    defp quote_table(nil, name), do: quote_table(name)

    defp quote_table({server, db, schema}, name),
      do: [
        quote_table(server),
        ".",
        quote_table(db),
        ".",
        quote_table(schema),
        ".",
        quote_table(name)
      ]

    defp quote_table({db, schema}, name),
      do: [quote_table(db), ".", quote_table(schema), ".", quote_table(name)]

    defp quote_table(prefix, name),
      do: [quote_table(prefix), ".", quote_table(name)]

    defp quote_table(name) when is_atom(name), do: quote_table(Atom.to_string(name))

    defp quote_table(name) do
      if String.contains?(name, "[") or String.contains?(name, "]") do
        error!(nil, "bad table name #{inspect(name)} '[' and ']' are not permitted")
      end

      "[#{name}]"
    end

    defp unquoted_name(prefix, name, column_name),
      do: unquoted_name(unquoted_name(prefix, name), column_name)

    defp unquoted_name(nil, name), do: unquoted_name(name)

    defp unquoted_name(prefix, name) do
      prefix = if is_atom(prefix), do: Atom.to_string(prefix), else: prefix
      name = if is_atom(name), do: Atom.to_string(name), else: name

      [prefix, ".", name]
    end

    defp unquoted_name(name) when is_atom(name), do: unquoted_name(Atom.to_string(name))

    defp unquoted_name(name) do
      if String.contains?(name, ["[", "]"]) do
        error!(nil, "bad table name #{inspect(name)} '[' and ']' are not permitted")
      end

      name
    end

    defp intersperse_reduce(list, separator, user_acc, reducer, acc \\ [])

    defp intersperse_reduce([], _separator, user_acc, _reducer, acc),
      do: {acc, user_acc}

    defp intersperse_reduce([elem], _separator, user_acc, reducer, acc) do
      {elem, user_acc} = reducer.(elem, user_acc)
      {[acc | elem], user_acc}
    end

    defp intersperse_reduce([elem | rest], separator, user_acc, reducer, acc) do
      {elem, user_acc} = reducer.(elem, user_acc)
      intersperse_reduce(rest, separator, user_acc, reducer, [acc, elem, separator])
    end

    defp if_do(condition, value) do
      if condition, do: value, else: []
    end

    defp escape_string(value) when is_binary(value) do
      value |> :binary.replace("'", "''", [:global])
    end

    defp ecto_to_db(type, size, precision, scale, query \\ nil)

    defp ecto_to_db({:array, _}, _, _, _, query),
      do: error!(query, "Array type is not supported by TDS")

    defp ecto_to_db(:id, _, _, _, _), do: "bigint"
    defp ecto_to_db(:serial, _, _, _, _), do: "int IDENTITY(1,1)"
    defp ecto_to_db(:bigserial, _, _, _, _), do: "bigint IDENTITY(1,1)"
    defp ecto_to_db(:binary_id, _, _, _, _), do: "uniqueidentifier"
    defp ecto_to_db(:boolean, _, _, _, _), do: "bit"
    defp ecto_to_db(:string, nil, _, _, _), do: "nvarchar(255)"
    defp ecto_to_db(:string, :max, _, _, _), do: "nvarchar(max)"
    defp ecto_to_db(:string, s, _, _, _) when s in 1..4_000, do: "nvarchar(#{s})"
    defp ecto_to_db(:float, nil, _, _, _), do: "float"
    defp ecto_to_db(:float, s, _, _, _) when s in 1..53, do: "float(#{s})"
    defp ecto_to_db(:binary, nil, _, _, _), do: "varbinary(max)"
    defp ecto_to_db(:binary, s, _, _, _) when s in 1..8_000, do: "varbinary(#{s})"
    defp ecto_to_db(:uuid, _, _, _, _), do: "uniqueidentifier"
    defp ecto_to_db(:map, nil, _, _, _), do: "nvarchar(max)"
    defp ecto_to_db(:map, s, _, _, _) when s in 0..4_000, do: "nvarchar(#{s})"
    defp ecto_to_db({:map, _}, nil, _, _, _), do: "nvarchar(max)"
    defp ecto_to_db({:map, _}, s, _, _, _) when s in 1..4_000, do: "nvarchar(#{s})"
    defp ecto_to_db(:time, _, _, _, _), do: "time(0)"
    defp ecto_to_db(:time_usec, _, p, _, _) when p in 0..7, do: "time(#{p})"
    defp ecto_to_db(:time_usec, _, _, _, _), do: "time(6)"
    defp ecto_to_db(:utc_datetime, _, _, _, _), do: "datetime"
    defp ecto_to_db(:utc_datetime_usec, _, p, _, _) when p in 0..7, do: "datetime2(#{p})"
    defp ecto_to_db(:utc_datetime_usec, _, _, _, _), do: "datetime2(6)"
    defp ecto_to_db(:naive_datetime, _, _, _, _), do: "datetime"
    defp ecto_to_db(:naive_datetime_usec, _, p, _, _) when p in 0..7, do: "datetime2(#{p})"
    defp ecto_to_db(:naive_datetime_usec, _, _, _, _), do: "datetime2(6)"

    defp ecto_to_db(other, size, _, _, _) when is_integer(size) do
      "#{Atom.to_string(other)}(#{size})"
    end

    defp ecto_to_db(other, _, precision, scale, _) when is_integer(precision) do
      "#{Atom.to_string(other)}(#{precision},#{scale || 0})"
    end

    defp ecto_to_db(atom, nil, nil, nil, _) when is_atom(atom) do
      Atom.to_string(atom)
    end

    defp ecto_to_db(type, _, _, _, _) do
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

    defp if_table_not_exists(condition, name, prefix) do
      if_do(condition, [
        "IF NOT EXISTS (SELECT * FROM [INFORMATION_SCHEMA].[TABLES] ",
        "WHERE ",
        "[TABLE_NAME] = ",
        ?',
        "#{name}",
        ?',
        if_do(prefix != nil, [
          " AND [TABLE_SCHEMA] = ",
          ?',
          "#{prefix}",
          ?'
        ]),
        ") "
      ])
    end

    defp if_table_exists(condition, name, prefix) do
      if_do(condition, [
        "IF EXISTS (SELECT * FROM [INFORMATION_SCHEMA].[TABLES] ",
        "WHERE ",
        "[TABLE_NAME] = ",
        ?',
        "#{name}",
        ?',
        if_do(prefix != nil, [
          " AND [TABLE_SCHEMA] = ",
          ?',
          "#{prefix}",
          ?'
        ]),
        ") "
      ])
    end

    defp if_column_exists(prefix, table, column_name) do
      [
        "IF EXISTS (SELECT 1 FROM [sys].[columns] ",
        "WHERE [name] = N'#{column_name}'  AND ",
        "[object_id] = OBJECT_ID(N'",
        if_do(prefix != nil, ["#{prefix}", ?.]),
        "#{table}",
        "')) "
      ]
    end

    defp if_column_not_exists(prefix, table, column_name) do
      [
        "IF NOT EXISTS (SELECT 1 FROM [sys].[columns] ",
        "WHERE [name] = N'#{column_name}' AND ",
        "[object_id] = OBJECT_ID(N'",
        if_do(prefix != nil, ["#{prefix}", ?.]),
        "#{table}",
        "')) "
      ]
    end

    defp list_param_to_args(idx, length) do
      Enum.map_join(1..length, ",", &"@#{idx + &1}")
    end

    defp as_string(atom) when is_atom(atom), do: Atom.to_string(atom)
    defp as_string(str), do: str

    defp if_index_exists(condition, index_name, table_name) do
      if_do(condition, [
        "IF EXISTS (SELECT name FROM sys.indexes WHERE name = N'",
        as_string(index_name),
        "' AND object_id = OBJECT_ID(N'",
        as_string(table_name),
        "')) "
      ])
    end

    defp if_index_not_exists(condition, index_name, table_name) do
      if_do(condition, [
        "IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'",
        as_string(index_name),
        "' AND object_id = OBJECT_ID(N'",
        as_string(table_name),
        "')) "
      ])
    end

    defp if_check_constraint_exists(condition, name, prefix) do
      if_do(condition, [
        "IF NOT EXISTS (SELECT * ",
        "FROM [INFORMATION_SCHEMA].[CHECK_CONSTRAINTS] ",
        "WHERE [CONSTRAINT_NAME] = N'#{name}'",
        if_do(prefix != nil, [
          " AND [CONSTRAINT_SCHEMA] = N'#{prefix}'"
        ]),
        ") "
      ])
    end

    # types
    # "U" - table,
    # "C", "PK", "UQ", "F ", "D " - constraints
    defp if_object_exists(name, type, statement) do
      [
        "IF (OBJECT_ID(N'",
        name,
        "', '",
        type,
        "') IS NOT NULL) ",
        statement
      ]
    end

    defp if_exists_drop_constraint(name, statement_prefix) do
      [
        if_object_exists(
          name,
          "D",
          "#{statement_prefix}DROP CONSTRAINT #{name}; "
        )
      ]
    end
  end
end
