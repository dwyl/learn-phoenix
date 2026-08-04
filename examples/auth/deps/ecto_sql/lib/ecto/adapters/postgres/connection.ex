if Code.ensure_loaded?(Postgrex) do
  defmodule Ecto.Adapters.Postgres.Connection do
    @moduledoc false

    @default_port 5432
    @behaviour Ecto.Adapters.SQL.Connection
    @explain_prepared_statement_name "ecto_explain_statement"

    ## Module and Options

    @impl true
    def child_spec(opts) do
      opts
      |> Keyword.put_new(:port, @default_port)
      |> Postgrex.child_spec()
    end

    @impl true
    def to_constraints(
          %Postgrex.Error{postgres: %{code: :unique_violation, constraint: constraint}},
          _opts
        ),
        do: [unique: constraint]

    def to_constraints(
          %Postgrex.Error{postgres: %{code: :foreign_key_violation, constraint: constraint}},
          _opts
        ),
        do: [foreign_key: constraint]

    def to_constraints(
          %Postgrex.Error{postgres: %{code: :exclusion_violation, constraint: constraint}},
          _opts
        ),
        do: [exclusion: constraint]

    def to_constraints(
          %Postgrex.Error{postgres: %{code: :check_violation, constraint: constraint}},
          _opts
        ),
        do: [check: constraint]

    # Postgres 9.2 and earlier does not provide the constraint field
    @impl true
    def to_constraints(
          %Postgrex.Error{postgres: %{code: :unique_violation, message: message}},
          _opts
        ) do
      case :binary.split(message, " unique constraint ") do
        [_, quoted] -> [unique: strip_quotes(quoted)]
        _ -> []
      end
    end

    def to_constraints(
          %Postgrex.Error{postgres: %{code: :foreign_key_violation, message: message}},
          _opts
        ) do
      case :binary.split(message, " foreign key constraint ") do
        [_, quoted] ->
          [quoted | _] = :binary.split(quoted, " on table ")
          [foreign_key: strip_quotes(quoted)]

        _ ->
          []
      end
    end

    def to_constraints(
          %Postgrex.Error{postgres: %{code: :exclusion_violation, message: message}},
          _opts
        ) do
      case :binary.split(message, " exclusion constraint ") do
        [_, quoted] -> [exclusion: strip_quotes(quoted)]
        _ -> []
      end
    end

    def to_constraints(
          %Postgrex.Error{postgres: %{code: :check_violation, message: message}},
          _opts
        ) do
      case :binary.split(message, " check constraint ") do
        [_, quoted] -> [check: strip_quotes(quoted)]
        _ -> []
      end
    end

    def to_constraints(_, _opts),
      do: []

    defp strip_quotes(quoted) do
      binary_part(quoted, 1, byte_size(quoted) - 2)
    end

    ## Query

    @impl true
    def prepare_execute(conn, name, sql, params, opts) do
      ensure_list_params!(params)

      case Postgrex.prepare_execute(conn, name, sql, params, opts) do
        {:error, %Postgrex.Error{postgres: %{pg_code: "22P02", message: message}} = error} ->
          context = """
          . If you are trying to query a JSON field, the parameter may need to be interpolated. \
          Instead of

              p.json["field"] != "value"

          do

              p.json["field"] != ^"value"
          """

          {:error, put_in(error.postgres.message, message <> context)}

        other ->
          other
      end
    end

    @impl true
    def query(conn, sql, params, opts) do
      ensure_list_params!(params)
      Postgrex.query(conn, sql, params, opts)
    end

    @impl true
    def query_many(_conn, _sql, _params, _opts) do
      raise RuntimeError, "query_many is not supported in the PostgreSQL adapter"
    end

    @impl true
    def execute(conn, %{ref: ref} = query, params, opts) do
      ensure_list_params!(params)

      case Postgrex.execute(conn, query, params, opts) do
        {:ok, %{ref: ^ref}, result} ->
          {:ok, result}

        {:ok, _, _} = ok ->
          ok

        {:error, %Postgrex.QueryError{} = err} ->
          {:reset, err}

        {:error, %Postgrex.Error{postgres: %{code: :feature_not_supported}} = err} ->
          {:reset, err}

        {:error, _} = error ->
          error
      end
    end

    @impl true
    def stream(conn, sql, params, opts) do
      ensure_list_params!(params)
      Postgrex.stream(conn, sql, params, opts)
    end

    defp ensure_list_params!(params) do
      unless is_list(params) do
        raise ArgumentError, "expected params to be a list, got: #{inspect(params)}"
      end
    end

    @parent_as __MODULE__
    alias Ecto.Query.{BooleanExpr, ByExpr, JoinExpr, QueryExpr, WithExpr}

    @impl true
    def all(query, as_prefix \\ []) do
      sources = create_names(query, as_prefix)
      {select_distinct, order_by_distinct} = distinct(query.distinct, sources, query)

      cte = cte(query, sources)
      from = from(query, sources)
      select = select(query, select_distinct, sources)
      join = join(query, sources)
      where = where(query, sources)
      group_by = group_by(query, sources)
      having = having(query, sources)
      window = window(query, sources)
      combinations = combinations(query, as_prefix)
      order_by = order_by(query, order_by_distinct, sources)
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
    def update_all(%{from: %{source: source}} = query, prefix \\ nil) do
      sources = create_names(query, [])
      cte = cte(query, sources)
      {from, name} = get_source(query, sources, 0, source)

      prefix = prefix || ["UPDATE ", from, " AS ", name | " SET "]
      fields = update_fields(query, sources)
      {join, wheres} = using_join(query, :update_all, "FROM", sources)
      where = where(%{query | wheres: wheres ++ query.wheres}, sources)

      [cte, prefix, fields, join, where | returning(query, sources)]
    end

    @impl true
    def delete_all(%{from: from} = query) do
      sources = create_names(query, [])
      cte = cte(query, sources)
      {from, name} = get_source(query, sources, 0, from)

      {join, wheres} = using_join(query, :delete_all, "USING", sources)
      where = where(%{query | wheres: wheres ++ query.wheres}, sources)

      [cte, "DELETE FROM ", from, " AS ", name, join, where | returning(query, sources)]
    end

    @impl true
    def insert(prefix, table, header, rows, on_conflict, returning, placeholders) do
      counter_offset = length(placeholders) + 1

      values =
        if header == [] do
          [" VALUES " | Enum.map_intersperse(rows, ?,, fn _ -> "(DEFAULT)" end)]
        else
          [" (", quote_names(header), ") " | insert_all(rows, counter_offset)]
        end

      [
        "INSERT INTO ",
        quote_name(prefix, table),
        insert_as(on_conflict),
        values,
        on_conflict(on_conflict) | returning(returning)
      ]
    end

    defp insert_as({%{sources: sources}, _, _}) do
      {_expr, name, _schema} = create_name(sources, 0, [])
      [" AS " | name]
    end

    defp insert_as({_, _, _}) do
      []
    end

    defp on_conflict({:raise, _, []}),
      do: []

    defp on_conflict({:nothing, _, targets}),
      do: [" ON CONFLICT ", conflict_target(targets) | "DO NOTHING"]

    defp on_conflict({fields, _, targets}) when is_list(fields),
      do: [" ON CONFLICT ", conflict_target!(targets), "DO " | replace(fields)]

    defp on_conflict({query, _, targets}),
      do: [" ON CONFLICT ", conflict_target!(targets), "DO " | update_all(query, "UPDATE SET ")]

    defp conflict_target!([]),
      do: error!(nil, "the :conflict_target option is required on upserts by PostgreSQL")

    defp conflict_target!(target),
      do: conflict_target(target)

    defp conflict_target({:unsafe_fragment, fragment}),
      do: [fragment, ?\s]

    defp conflict_target([]),
      do: []

    defp conflict_target(targets),
      do: [?(, quote_names(targets), ?), ?\s]

    defp replace(fields) do
      [
        "UPDATE SET "
        | Enum.map_intersperse(fields, ?,, fn field ->
            quoted = quote_name(field)
            [quoted, " = ", "EXCLUDED." | quoted]
          end)
      ]
    end

    defp insert_all(query = %Ecto.Query{}, _counter) do
      [?(, all(query), ?)]
    end

    defp insert_all(rows, counter) do
      [
        "VALUES ",
        intersperse_reduce(rows, ?,, counter, fn row, counter ->
          {row, counter} = insert_each(row, counter)
          {[?(, row, ?)], counter}
        end)
        |> elem(0)
      ]
    end

    defp insert_each(values, counter) do
      intersperse_reduce(values, ?,, counter, fn
        nil, counter ->
          {"DEFAULT", counter}

        {%Ecto.Query{} = query, params_counter}, counter ->
          {[?(, all(query), ?)], counter + params_counter}

        {:placeholder, placeholder_index}, counter ->
          {[?$ | placeholder_index], counter}

        _, counter ->
          {[?$ | Integer.to_string(counter)], counter + 1}
      end)
    end

    @impl true
    def update(prefix, table, fields, filters, returning) do
      {fields, count} =
        intersperse_reduce(fields, ", ", 1, fn field, acc ->
          {[quote_name(field), " = $" | Integer.to_string(acc)], acc + 1}
        end)

      {filters, _count} =
        intersperse_reduce(filters, " AND ", count, fn
          {field, nil}, acc ->
            {[quote_name(field), " IS NULL"], acc}

          {field, _value}, acc ->
            {[quote_name(field), " = $" | Integer.to_string(acc)], acc + 1}
        end)

      [
        "UPDATE ",
        quote_name(prefix, table),
        " SET ",
        fields,
        " WHERE ",
        filters | returning(returning)
      ]
    end

    @impl true
    def delete(prefix, table, filters, returning) do
      {filters, _} =
        intersperse_reduce(filters, " AND ", 1, fn
          {field, nil}, acc ->
            {[quote_name(field), " IS NULL"], acc}

          {field, _value}, acc ->
            {[quote_name(field), " = $" | Integer.to_string(acc)], acc + 1}
        end)

      ["DELETE FROM ", quote_name(prefix, table), " WHERE ", filters | returning(returning)]
    end

    @impl true
    def explain_query(conn, query, params, opts) do
      {explain_opts, opts} =
        Keyword.split(
          opts,
          ~w[analyze verbose costs settings buffers timing summary format plan]a
        )

      {plan_type, explain_opts} = Keyword.pop(explain_opts, :plan)
      fallback_generic? = plan_type == :fallback_generic

      result =
        cond do
          fallback_generic? and explain_opts[:analyze] ->
            raise ArgumentError,
                  "analyze cannot be used with a `:fallback_generic` explain plan " <>
                    "as the actual parameter values are ignored under this plan type." <>
                    "You may either change the plan type to `:custom` or remove the `:analyze` option."

          fallback_generic? ->
            explain_queries = build_fallback_generic_queries(query, length(params), explain_opts)
            fallback_generic_query(conn, explain_queries, opts)

          true ->
            query(conn, build_explain_query(query, explain_opts), params, opts)
        end

      map_format? = explain_opts[:format] == :map

      case result do
        {:ok, %Postgrex.Result{rows: rows}} when map_format? ->
          {:ok, List.flatten(rows)}

        {:ok, %Postgrex.Result{rows: rows}} ->
          {:ok, Enum.map_join(rows, "\n", & &1)}

        error ->
          error
      end
    end

    def build_fallback_generic_queries(query, num_params, opts) do
      prepare_args =
        if num_params > 0,
          do: ["( ", Enum.map_intersperse(1..num_params, ", ", fn _ -> "unknown" end), " )"],
          else: []

      prepare =
        [
          "PREPARE ",
          @explain_prepared_statement_name,
          prepare_args,
          " AS ",
          query
        ]
        |> IO.iodata_to_binary()

      set = "SET LOCAL plan_cache_mode = force_generic_plan"

      execute_args =
        if num_params > 0,
          do: ["( ", Enum.map_intersperse(1..num_params, ", ", fn _ -> "NULL" end), " )"],
          else: []

      execute =
        [
          "EXPLAIN ",
          build_explain_opts(opts),
          "EXECUTE ",
          @explain_prepared_statement_name,
          execute_args
        ]
        |> IO.iodata_to_binary()

      deallocate = "DEALLOCATE #{@explain_prepared_statement_name}"

      {prepare, set, execute, deallocate}
    end

    def build_explain_query(query, opts) do
      ["EXPLAIN ", build_explain_opts(opts), query]
      |> IO.iodata_to_binary()
    end

    defp build_explain_opts([]), do: []

    defp build_explain_opts(opts) do
      {analyze, opts} = Keyword.pop(opts, :analyze)
      {verbose, opts} = Keyword.pop(opts, :verbose)

      # Given only ANALYZE or VERBOSE opts we assume the legacy format
      # to support all Postgres versions, otherwise assume the new
      # syntax supported since v9.0
      case opts do
        [] ->
          [
            if_do(quote_boolean(analyze) == "TRUE", "ANALYZE "),
            if_do(quote_boolean(verbose) == "TRUE", "VERBOSE ")
          ]

        opts ->
          opts =
            ([analyze: analyze, verbose: verbose] ++ opts)
            |> Enum.reduce([], fn
              {_, nil}, acc ->
                acc

              {:format, value}, acc ->
                [String.upcase("#{format_to_sql(value)}") | acc]

              {opt, value}, acc ->
                [String.upcase("#{opt} #{quote_boolean(value)}") | acc]
            end)
            |> Enum.reverse()
            |> Enum.join(", ")

          ["( ", opts, " ) "]
      end
    end

    defp fallback_generic_query(conn, queries, opts) do
      {prepare, set, execute, deallocate} = queries

      with {:ok, _} <- query(conn, prepare, [], opts),
           {:ok, _} <- query(conn, set, [], opts),
           {:ok, result} <- query(conn, execute, [], opts),
           {:ok, _} <- query(conn, deallocate, [], opts) do
        {:ok, result}
      end
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
      ilike: " ILIKE ",
      like: " LIKE "
    ]

    @binary_ops Keyword.keys(binary_ops)

    Enum.map(binary_ops, fn {op, str} ->
      defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
    end)

    defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

    defp select(%{select: %{fields: fields}} = query, select_distinct, sources) do
      ["SELECT", select_distinct, ?\s | select_fields(fields, sources, query)]
    end

    defp select_fields([], _sources, _query),
      do: "TRUE"

    defp select_fields(fields, sources, query) do
      Enum.map_intersperse(fields, ", ", fn
        {:&, _, [idx]} ->
          case elem(sources, idx) do
            {nil, source, nil} ->
              error!(
                query,
                "PostgreSQL adapter does not support selecting all fields from fragment #{source}. " <>
                  "Please specify exactly which fields you want to select"
              )

            {source, _, nil} ->
              error!(
                query,
                "PostgreSQL adapter does not support selecting all fields from #{source} without a schema. " <>
                  "Please specify a schema or specify exactly which fields you want to select"
              )

            {_, source, _} ->
              source
          end

        {key, value} ->
          [expr(value, sources, query), " AS " | quote_name(key)]

        value ->
          expr(value, sources, query)
      end)
    end

    defp distinct(nil, _, _), do: {[], []}
    defp distinct(%ByExpr{expr: []}, _, _), do: {[], []}
    defp distinct(%ByExpr{expr: true}, _, _), do: {" DISTINCT", []}
    defp distinct(%ByExpr{expr: false}, _, _), do: {[], []}

    defp distinct(%ByExpr{expr: exprs}, sources, query) do
      {[
         " DISTINCT ON (",
         Enum.map_intersperse(exprs, ", ", fn {_, expr} -> expr(expr, sources, query) end),
         ?)
       ], exprs}
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

    defp cte_expr({name, opts, cte}, sources, query) do
      materialized_opt =
        case opts[:materialized] do
          nil -> ""
          true -> "MATERIALIZED"
          false -> "NOT MATERIALIZED"
        end

      operation_opt = Map.get(opts, :operation)

      [quote_name(name), " AS ", materialized_opt, cte_query(cte, sources, query, operation_opt)]
    end

    defp cte_query(query, sources, parent_query, nil) do
      cte_query(query, sources, parent_query, :all)
    end

    defp cte_query(%Ecto.Query{} = query, sources, parent_query, :update_all) do
      query = put_in(query.aliases[@parent_as], {parent_query, sources})
      ["(", update_all(query), ")"]
    end

    defp cte_query(%Ecto.Query{} = query, sources, parent_query, :delete_all) do
      query = put_in(query.aliases[@parent_as], {parent_query, sources})
      ["(", delete_all(query), ")"]
    end

    defp cte_query(%Ecto.Query{} = query, _sources, _parent_query, :insert_all) do
      error!(query, "Postgres adapter does not support CTE operation :insert_all")
    end

    defp cte_query(%Ecto.Query{} = query, sources, parent_query, :all) do
      query = put_in(query.aliases[@parent_as], {parent_query, sources})
      ["(", all(query, subquery_as_prefix(sources)), ")"]
    end

    defp cte_query(%QueryExpr{expr: expr}, sources, query, _operation) do
      expr(expr, sources, query)
    end

    defp update_fields(%{updates: updates} = query, sources) do
      for(
        %{expr: expr} <- updates,
        {op, kw} <- expr,
        {key, value} <- kw,
        do: update_op(op, key, value, sources, query)
      )
      |> Enum.intersperse(", ")
    end

    defp update_op(:set, key, value, sources, query) do
      [quote_name(key), " = " | expr(value, sources, query)]
    end

    defp update_op(:inc, key, value, sources, query) do
      [
        quote_name(key),
        " = ",
        quote_qualified_name(key, sources, 0),
        " + "
        | expr(value, sources, query)
      ]
    end

    defp update_op(:push, key, value, sources, query) do
      [
        quote_name(key),
        " = array_append(",
        quote_qualified_name(key, sources, 0),
        ", ",
        expr(value, sources, query),
        ?)
      ]
    end

    defp update_op(:pull, key, value, sources, query) do
      [
        quote_name(key),
        " = array_remove(",
        quote_qualified_name(key, sources, 0),
        ", ",
        expr(value, sources, query),
        ?)
      ]
    end

    defp update_op(command, _key, _value, _sources, query) do
      error!(query, "unknown update operation #{inspect(command)} for PostgreSQL")
    end

    defp using_join(%{joins: []}, _kind, _prefix, _sources), do: {[], []}

    defp using_join(%{joins: joins} = query, :update_all, prefix, sources) do
      {inner_joins, other_joins} = Enum.split_while(joins, &(&1.qual == :inner))

      if inner_joins == [] and other_joins != [] do
        error!(
          query,
          "Need at least one inner join at the beginning to use other joins with update_all"
        )
      end

      froms =
        Enum.map_intersperse(inner_joins, ", ", fn
          %JoinExpr{qual: :inner, ix: ix, source: source} ->
            {join, name} = get_source(query, sources, ix, source)
            [join, " AS " | [name]]
        end)

      join_clauses = join(%{query | joins: other_joins}, sources)

      wheres =
        for %JoinExpr{on: %QueryExpr{expr: value} = expr} <- inner_joins,
            value != true,
            do: expr |> Map.put(:__struct__, BooleanExpr) |> Map.put(:op, :and)

      {[?\s, prefix, ?\s, froms | join_clauses], wheres}
    end

    defp using_join(%{joins: joins} = query, kind, prefix, sources) do
      froms =
        Enum.map_intersperse(joins, ", ", fn
          %JoinExpr{qual: :inner, ix: ix, source: source} ->
            {join, name} = get_source(query, sources, ix, source)
            [join, " AS " | name]

          %JoinExpr{qual: qual} ->
            error!(query, "PostgreSQL supports only inner joins on #{kind}, got: `#{qual}`")
        end)

      wheres =
        for %JoinExpr{on: %QueryExpr{expr: value} = expr} <- joins,
            value != true,
            do: expr |> Map.put(:__struct__, BooleanExpr) |> Map.put(:op, :and)

      {[?\s, prefix, ?\s | froms], wheres}
    end

    defp join(%{joins: []}, _sources), do: []

    defp join(%{joins: joins} = query, sources) do
      [
        ?\s
        | Enum.map_intersperse(joins, ?\s, fn
            %JoinExpr{
              on: %QueryExpr{expr: expr},
              qual: qual,
              ix: ix,
              source: source,
              hints: hints
            } ->
              if hints != [] do
                error!(query, "table hints are not supported by PostgreSQL")
              end

              {join, name} = get_source(query, sources, ix, source)
              [join_qual(qual, query), join, " AS ", name | join_on(qual, expr, sources, query)]
          end)
      ]
    end

    defp join_on(:cross, true, _sources, _query), do: []
    defp join_on(:cross_lateral, true, _sources, _query), do: []
    defp join_on(_qual, expr, sources, query), do: [" ON " | expr(expr, sources, query)]

    defp join_qual(:inner, _), do: "INNER JOIN "
    defp join_qual(:inner_lateral, _), do: "INNER JOIN LATERAL "
    defp join_qual(:left, _), do: "LEFT OUTER JOIN "
    defp join_qual(:left_lateral, _), do: "LEFT OUTER JOIN LATERAL "
    defp join_qual(:right, _), do: "RIGHT OUTER JOIN "
    defp join_qual(:full, _), do: "FULL OUTER JOIN "
    defp join_qual(:cross, _), do: "CROSS JOIN "
    defp join_qual(:cross_lateral, _), do: "CROSS JOIN LATERAL "

    defp join_qual(qual, query),
      do:
        error!(
          query,
          "join qualifier #{inspect(qual)} is not supported in the PostgreSQL adapter"
        )

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
        | Enum.map_intersperse(group_bys, ", ", fn
            %ByExpr{expr: expr} ->
              Enum.map_intersperse(expr, ", ", &expr(&1, sources, query))
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

    defp order_by(%{order_bys: []}, _distinct, _sources), do: []

    defp order_by(%{order_bys: order_bys} = query, distinct, sources) do
      order_bys = Enum.flat_map(order_bys, & &1.expr)
      order_bys = order_by_concat(distinct, order_bys)
      [" ORDER BY " | Enum.map_intersperse(order_bys, ", ", &order_by_expr(&1, sources, query))]
    end

    defp order_by_concat([head | left], [head | right]), do: [head | order_by_concat(left, right)]
    defp order_by_concat(left, right), do: left ++ right

    defp order_by_expr({dir, expr}, sources, query) do
      str = expr(expr, sources, query)

      case dir do
        :asc -> str
        :asc_nulls_last -> [str | " ASC NULLS LAST"]
        :asc_nulls_first -> [str | " ASC NULLS FIRST"]
        :desc -> [str | " DESC"]
        :desc_nulls_last -> [str | " DESC NULLS LAST"]
        :desc_nulls_first -> [str | " DESC NULLS FIRST"]
      end
    end

    defp limit(%{limit: nil}, _sources), do: []

    defp limit(%{limit: %{with_ties: true}, order_bys: []} = query, _sources) do
      error!(
        query,
        "PostgreSQL adapter requires an `order_by` clause if the " <>
          "`:with_ties` limit option is `true`"
      )
    end

    defp limit(%{limit: %{expr: expr, with_ties: true}} = query, sources) do
      [" FETCH FIRST ", expr(expr, sources, query) | " ROWS WITH TIES"]
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

    defp paren_expr(expr, sources, query) do
      [?(, expr(expr, sources, query), ?)]
    end

    defp expr({:^, [], [ix]}, _sources, _query) do
      [?$ | Integer.to_string(ix + 1)]
    end

    defp expr({{:., _, [{:parent_as, _, [as]}, field]}, _, []}, _sources, query)
         when is_atom(field) or is_binary(field) do
      {ix, sources} = get_parent_sources_ix(query, as)
      quote_qualified_name(field, sources, ix)
    end

    defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query)
         when is_atom(field) or is_binary(field) do
      quote_qualified_name(field, sources, idx)
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

    defp expr({:in, _, [left, {:^, _, [ix, _]}]}, sources, query) do
      [expr(left, sources, query), " = ANY($", Integer.to_string(ix + 1), ?)]
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

    defp expr(%Ecto.SubQuery{query: query}, sources, parent_query) do
      combinations =
        Enum.map(query.combinations, fn {type, combination_query} ->
          {type, put_in(combination_query.aliases[@parent_as], {parent_query, sources})}
        end)

      query = put_in(query.combinations, combinations)
      query = put_in(query.aliases[@parent_as], {parent_query, sources})
      [?(, all(query, subquery_as_prefix(sources)), ?)]
    end

    defp expr({:fragment, _, [kw]}, _sources, query) when is_list(kw) or tuple_size(kw) == 3 do
      error!(query, "PostgreSQL adapter does not support keyword or interpolated fragments")
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
      Enum.map_join(1..length, ",", &"$#{idx + &1}")
    end

    defp expr({:selected_as, _, [name]}, _sources, _query) do
      [quote_name(name)]
    end

    defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
      [
        expr(datetime, sources, query),
        type_unless_typed(datetime, "timestamp"),
        " + ",
        interval(count, interval, sources, query)
      ]
    end

    defp expr({:date_add, _, [date, count, interval]}, sources, query) do
      [
        ?(,
        expr(date, sources, query),
        type_unless_typed(date, "date"),
        " + ",
        interval(count, interval, sources, query) | ")::date"
      ]
    end

    defp expr({:json_extract_path, _, [expr, path]}, sources, query) do
      json_extract_path(expr, path, sources, query)
    end

    defp expr({:filter, _, [agg, filter]}, sources, query) do
      aggregate = expr(agg, sources, query)
      [aggregate, " FILTER (WHERE ", expr(filter, sources, query), ?)]
    end

    defp expr({:over, _, [agg, name]}, sources, query) when is_atom(name) do
      aggregate = expr(agg, sources, query)
      [aggregate, " OVER " | quote_name(name)]
    end

    defp expr({:over, _, [agg, kw]}, sources, query) do
      aggregate = expr(agg, sources, query)
      [aggregate, " OVER ", window_exprs(kw, sources, query)]
    end

    defp expr({:{}, _, elems}, sources, query) do
      [?(, Enum.map_intersperse(elems, ?,, &expr(&1, sources, query)), ?)]
    end

    defp expr({:count, _, []}, _sources, _query), do: "count(*)"

    defp expr({:==, _, [{:json_extract_path, _, [expr, path]} = left, right]}, sources, query)
         when is_binary(right) or is_integer(right) or is_boolean(right) do
      case Enum.split(path, -1) do
        {path, [last]} when is_binary(last) ->
          extracted = json_extract_path(expr, path, sources, query)
          [?(, extracted, "@>'{", escape_json(last), ": ", escape_json(right) | "}')"]

        _ ->
          [maybe_paren(left, sources, query), " = " | maybe_paren(right, sources, query)]
      end
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
          [maybe_paren(left, sources, query), op | maybe_paren(right, sources, query)]

        {:fun, fun} ->
          [fun, ?(, modifier, Enum.map_intersperse(args, ", ", &expr(&1, sources, query)), ?)]
      end
    end

    defp expr([], _sources, _query) do
      # We cannot compare in postgres with the empty array
      # i. e. `where array_column = ARRAY[];`
      # as that will result in an error:
      #   ERROR:  cannot determine type of empty array
      #   HINT:  Explicitly cast to the desired type, for example ARRAY[]::integer[].
      #
      # On the other side comparing with '{}' works
      # because '{}' represents the pseudo-type "unknown"
      # and thus the type gets inferred based on the column
      # it is being compared to so `where array_column = '{}';` works.
      "'{}'"
    end

    defp expr(list, sources, query) when is_list(list) do
      ["ARRAY[", Enum.map_intersperse(list, ?,, &expr(&1, sources, query)), ?]]
    end

    defp expr(%Decimal{} = decimal, _sources, _query) do
      Decimal.to_string(decimal, :normal)
    end

    defp expr(%Ecto.Query.Tagged{value: binary, type: :binary}, _sources, _query)
         when is_binary(binary) do
      ["'\\x", Base.encode16(binary, case: :lower) | "'::bytea"]
    end

    defp expr(%Ecto.Query.Tagged{value: bitstring, type: :bitstring}, _sources, _query)
         when is_bitstring(bitstring) do
      bitstring_literal(bitstring)
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query) do
      [maybe_paren(other, sources, query), ?:, ?: | tagged_to_db(type)]
    end

    defp expr(nil, _sources, _query), do: "NULL"
    defp expr(true, _sources, _query), do: "TRUE"
    defp expr(false, _sources, _query), do: "FALSE"

    defp expr(literal, _sources, _query) when is_binary(literal) do
      [?\', escape_string(literal), ?\']
    end

    defp expr(literal, _sources, _query) when is_integer(literal) do
      Integer.to_string(literal)
    end

    defp expr(literal, _sources, _query) when is_float(literal) do
      [Float.to_string(literal) | "::float"]
    end

    defp expr(expr, _sources, query) do
      error!(query, "unsupported expression: #{inspect(expr)}")
    end

    defp json_extract_path(expr, [], sources, query) do
      expr(expr, sources, query)
    end

    defp json_extract_path(expr, path, sources, query) do
      path = Enum.map_intersperse(path, ?,, &escape_json(&1, sources, query))
      [?(, expr(expr, sources, query), "#>array[", path, "]::text[])"]
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
        {[?$, Integer.to_string(idx), ?:, ?: | tagged_to_db(type)], idx + 1}
      end)
    end

    defp type_unless_typed(%Ecto.Query.Tagged{}, _type), do: []
    defp type_unless_typed(_, type), do: [?:, ?: | type]

    # Always use the largest possible type for integers
    defp tagged_to_db(:id), do: "bigint"
    defp tagged_to_db(:integer), do: "bigint"
    defp tagged_to_db({:array, type}), do: [tagged_to_db(type), ?[, ?]]
    defp tagged_to_db(type), do: ecto_to_db(type)

    defp interval(count, interval, _sources, _query) when is_integer(count) do
      ["interval '", String.Chars.Integer.to_string(count), ?\s, interval, ?\']
    end

    defp interval(count, interval, _sources, _query) when is_float(count) do
      count = :erlang.float_to_binary(count, [:compact, decimals: 16])
      ["interval '", count, ?\s, interval, ?\']
    end

    defp interval(count, interval, sources, query) do
      [?(, expr(count, sources, query), "::numeric * ", interval(1, interval, sources, query), ?)]
    end

    defp maybe_paren({op, _, [_, _]} = expr, sources, query) when op in @binary_ops,
      do: paren_expr(expr, sources, query)

    defp maybe_paren({:is_nil, _, [_]} = expr, sources, query),
      do: paren_expr(expr, sources, query)

    defp maybe_paren(expr, sources, query),
      do: expr(expr, sources, query)

    defp returning(%{select: nil}, _sources),
      do: []

    defp returning(%{select: %{fields: fields}} = query, sources),
      do: [" RETURNING " | select_fields(fields, sources, query)]

    defp returning([]),
      do: []

    defp returning(returning),
      do: [" RETURNING " | quote_names(returning)]

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
          {quote_name(prefix, table), name, schema}

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
      table_name = quote_name(table.prefix, table.name)

      query = [
        "CREATE TABLE ",
        if_do(command == :create_if_not_exists, "IF NOT EXISTS "),
        table_name,
        ?\s,
        ?(,
        column_definitions(table, columns),
        pk_definition(columns, ", "),
        ?),
        options_expr(table.options)
      ]

      [query] ++
        comments_on("TABLE", table_name, table.comment) ++
        comments_for_columns(table_name, columns)
    end

    def execute_ddl({command, %Table{} = table, mode}) when command in @drops do
      [
        [
          "DROP TABLE ",
          if_do(command == :drop_if_exists, "IF EXISTS "),
          quote_name(table.prefix, table.name),
          drop_mode(mode)
        ]
      ]
    end

    def execute_ddl({:alter, %Table{} = table, changes}) do
      table_name = quote_name(table.prefix, table.name)

      query = [
        "ALTER TABLE ",
        table_name,
        ?\s,
        column_changes(table, changes),
        pk_definition(changes, ", ADD ")
      ]

      [query] ++
        comments_on("TABLE", table_name, table.comment) ++
        comments_for_columns(table_name, changes)
    end

    def execute_ddl({command, %Index{} = index}) when command in @creates do
      fields = Enum.map_intersperse(index.columns, ", ", &index_expr/1)
      include_fields = Enum.map_intersperse(index.include, ", ", &include_expr/1)

      maybe_nulls_distinct =
        case index.nulls_distinct do
          nil -> []
          true -> " NULLS DISTINCT"
          false -> " NULLS NOT DISTINCT"
        end

      queries = [
        [
          "CREATE ",
          if_do(index.unique, "UNIQUE "),
          "INDEX ",
          if_do(index.concurrently, "CONCURRENTLY "),
          if_do(command == :create_if_not_exists, "IF NOT EXISTS "),
          quote_name(index.name),
          " ON ",
          if_do(index.only, "ONLY "),
          quote_name(index.prefix, index.table),
          if_do(index.using, [" USING ", to_string(index.using)]),
          ?\s,
          ?(,
          fields,
          ?),
          if_do(include_fields != [], [" INCLUDE ", ?(, include_fields, ?)]),
          maybe_nulls_distinct,
          if_do(index.options != nil, [" WITH ", ?(, index.options, ?)]),
          if_do(index.where, [" WHERE ", to_string(index.where)])
        ]
      ]

      queries ++ comments_on("INDEX", quote_name(index.prefix, index.name), index.comment)
    end

    def execute_ddl({command, %Index{} = index, mode}) when command in @drops do
      [
        [
          "DROP INDEX ",
          if_do(index.concurrently, "CONCURRENTLY "),
          if_do(command == :drop_if_exists, "IF EXISTS "),
          quote_name(index.prefix, index.name),
          drop_mode(mode)
        ]
      ]
    end

    def execute_ddl({:rename, %Index{} = current_index, new_name}) do
      [
        [
          "ALTER INDEX ",
          quote_name(current_index.prefix, current_index.name),
          " RENAME TO ",
          quote_name(new_name)
        ]
      ]
    end

    def execute_ddl({:rename, %Table{} = current_table, %Table{} = new_table}) do
      [
        [
          "ALTER TABLE ",
          quote_name(current_table.prefix, current_table.name),
          " RENAME TO ",
          quote_name(nil, new_table.name)
        ]
      ]
    end

    def execute_ddl({:rename, %Table{} = table, current_column, new_column}) do
      [
        [
          "ALTER TABLE ",
          quote_name(table.prefix, table.name),
          " RENAME ",
          quote_name(current_column),
          " TO ",
          quote_name(new_column)
        ]
      ]
    end

    def execute_ddl({:create, %Constraint{} = constraint}) do
      table_name = quote_name(constraint.prefix, constraint.table)
      queries = [["ALTER TABLE ", table_name, " ADD ", new_constraint_expr(constraint)]]

      queries ++ comments_on("CONSTRAINT", constraint.name, constraint.comment, table_name)
    end

    def execute_ddl({command, %Constraint{} = constraint, mode}) when command in @drops do
      [
        [
          "ALTER TABLE ",
          quote_name(constraint.prefix, constraint.table),
          " DROP CONSTRAINT ",
          if_do(command == :drop_if_exists, "IF EXISTS "),
          quote_name(constraint.name),
          drop_mode(mode)
        ]
      ]
    end

    def execute_ddl(string) when is_binary(string), do: [string]

    def execute_ddl(keyword) when is_list(keyword),
      do: error!(nil, "PostgreSQL adapter does not support keyword lists in execute")

    @impl true
    def ddl_logs(%Postgrex.Result{} = result) do
      %{messages: messages} = result

      for message <- messages do
        %{message: message, severity: severity} = message

        {ddl_log_level(severity), message, []}
      end
    end

    @impl true
    def table_exists_query(table) do
      {"SELECT true FROM information_schema.tables WHERE table_name = $1 AND table_schema = current_schema() LIMIT 1",
       [table]}
    end

    defp drop_mode(:cascade), do: " CASCADE"
    defp drop_mode(:restrict), do: []

    # From https://www.postgresql.org/docs/current/protocol-error-fields.html.
    defp ddl_log_level("DEBUG"), do: :debug
    defp ddl_log_level("LOG"), do: :info
    defp ddl_log_level("INFO"), do: :info
    defp ddl_log_level("NOTICE"), do: :info
    defp ddl_log_level("WARNING"), do: :warn
    defp ddl_log_level("ERROR"), do: :error
    defp ddl_log_level("FATAL"), do: :error
    defp ddl_log_level("PANIC"), do: :error
    defp ddl_log_level(_severity), do: :info

    defp pk_definition(columns, prefix) do
      pks =
        for {action, name, _, opts} <- columns,
            action != :remove,
            opts[:primary_key],
            do: name

      case pks do
        [] -> []
        _ -> [prefix, "PRIMARY KEY (", quote_names(pks), ")"]
      end
    end

    defp comments_on(_object, _name, nil), do: []

    defp comments_on(object, name, comment) do
      [["COMMENT ON ", object, ?\s, name, " IS ", single_quote(comment)]]
    end

    defp comments_on(_object, _name, nil, _table_name), do: []

    defp comments_on(object, name, comment, table_name) do
      [
        [
          "COMMENT ON ",
          object,
          ?\s,
          quote_name(name),
          " ON ",
          table_name,
          " IS ",
          single_quote(comment)
        ]
      ]
    end

    defp comments_for_columns(table_name, columns) do
      Enum.flat_map(columns, fn
        {:remove, _column_name, _column_type, _opts} ->
          []

        {_operation, column_name, _column_type, opts} ->
          column_name = [table_name, ?. | quote_name(column_name)]
          comments_on("COLUMN", column_name, opts[:comment])

        _ ->
          []
      end)
    end

    defp column_definitions(table, columns) do
      Enum.map_intersperse(columns, ", ", &column_definition(table, &1))
    end

    defp column_definition(table, {:add, name, %Reference{} = ref, opts}) do
      [
        quote_name(name),
        ?\s,
        reference_column_type(ref.type, opts),
        column_options(ref.type, opts),
        ", ",
        reference_expr(ref, table, name)
      ]
    end

    defp column_definition(_table, {:add, name, type, opts}) do
      [quote_name(name), ?\s, column_type(type, opts), column_options(type, opts)]
    end

    defp column_changes(table, columns) do
      Enum.map_intersperse(columns, ", ", &column_change(table, &1))
    end

    defp column_change(table, {:add, name, %Reference{} = ref, opts}) do
      [
        "ADD COLUMN ",
        quote_name(name),
        ?\s,
        reference_column_type(ref.type, opts),
        column_options(ref.type, opts),
        ", ADD ",
        reference_expr(ref, table, name)
      ]
    end

    defp column_change(_table, {:add, name, type, opts}) do
      ["ADD COLUMN ", quote_name(name), ?\s, column_type(type, opts), column_options(type, opts)]
    end

    defp column_change(table, {:add_if_not_exists, name, %Reference{} = ref, opts}) do
      [
        "ADD COLUMN IF NOT EXISTS ",
        quote_name(name),
        ?\s,
        reference_column_type(ref.type, opts),
        column_options(ref.type, opts),
        ", ADD ",
        reference_expr(ref, table, name)
      ]
    end

    defp column_change(_table, {:add_if_not_exists, name, type, opts}) do
      [
        "ADD COLUMN IF NOT EXISTS ",
        quote_name(name),
        ?\s,
        column_type(type, opts),
        column_options(type, opts)
      ]
    end

    defp column_change(table, {:modify, name, %Reference{} = ref, opts}) do
      collation = Keyword.fetch(opts, :collation)

      [
        drop_reference_expr(opts[:from], table, name),
        "ALTER COLUMN ",
        quote_name(name),
        " TYPE ",
        reference_column_type(ref.type, opts),
        ", ADD ",
        reference_expr(ref, table, name),
        modify_null(name, opts),
        modify_default(name, ref.type, opts),
        collation_expr(collation)
      ]
    end

    defp column_change(table, {:modify, name, type, opts}) do
      collation = Keyword.fetch(opts, :collation)

      [
        drop_reference_expr(opts[:from], table, name),
        "ALTER COLUMN ",
        quote_name(name),
        " TYPE ",
        column_type(type, opts),
        modify_null(name, opts),
        modify_default(name, type, opts),
        collation_expr(collation)
      ]
    end

    defp column_change(_table, {:remove, name}), do: ["DROP COLUMN ", quote_name(name)]

    defp column_change(table, {:remove, name, %Reference{} = ref, _opts}) do
      [drop_reference_expr(ref, table, name), "DROP COLUMN ", quote_name(name)]
    end

    defp column_change(_table, {:remove, name, _type, _opts}),
      do: ["DROP COLUMN ", quote_name(name)]

    defp column_change(table, {:remove_if_exists, name, %Reference{} = ref}) do
      [
        drop_reference_if_exists_expr(ref, table, name),
        "DROP COLUMN IF EXISTS ",
        quote_name(name)
      ]
    end

    defp column_change(table, {:remove_if_exists, name, _type}),
      do: column_change(table, {:remove_if_exists, name})

    defp column_change(_table, {:remove_if_exists, name}),
      do: ["DROP COLUMN IF EXISTS ", quote_name(name)]

    defp modify_null(name, opts) do
      case Keyword.get(opts, :null) do
        true -> [", ALTER COLUMN ", quote_name(name), " DROP NOT NULL"]
        false -> [", ALTER COLUMN ", quote_name(name), " SET NOT NULL"]
        nil -> []
      end
    end

    defp modify_default(name, type, opts) do
      case Keyword.fetch(opts, :default) do
        {:ok, val} ->
          [", ALTER COLUMN ", quote_name(name), " SET", default_expr({:ok, val}, type)]

        :error ->
          []
      end
    end

    defp column_options(type, opts) do
      default = Keyword.fetch(opts, :default)
      null = Keyword.get(opts, :null)
      collation = Keyword.fetch(opts, :collation)

      [default_expr(default, type), null_expr(null), collation_expr(collation)]
    end

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

    defp new_constraint_expr(%Constraint{exclude: exclude} = constraint)
         when is_binary(exclude) do
      [
        "CONSTRAINT ",
        quote_name(constraint.name),
        " EXCLUDE USING ",
        exclude,
        validate(constraint.validate)
      ]
    end

    defp default_expr({:ok, nil}, _type), do: " DEFAULT NULL"
    defp default_expr({:ok, literal}, type), do: [" DEFAULT ", default_type(literal, type)]
    defp default_expr(:error, _), do: []

    defp default_type(list, {:array, inner} = type) when is_list(list) do
      [
        "ARRAY[",
        Enum.map_intersperse(list, ?,, &default_type(&1, inner)),
        "]::",
        ecto_to_db(type)
      ]
    end

    defp default_type(literal, _type) when is_binary(literal) do
      if :binary.match(literal, <<0>>) == :nomatch and String.valid?(literal) do
        single_quote(literal)
      else
        encoded = "\\x" <> Base.encode16(literal, case: :lower)

        raise ArgumentError,
              "default values are interpolated as UTF-8 strings and cannot contain null bytes. " <>
                "`#{inspect(literal)}` is invalid. If you want to write it as a binary, use \"#{encoded}\", " <>
                "otherwise refer to PostgreSQL documentation for instructions on how to escape this SQL type"
      end
    end

    defp default_type(literal, _type) when is_bitstring(literal) do
      bitstring_literal(literal)
    end

    defp default_type(literal, _type) when is_number(literal), do: to_string(literal)
    defp default_type(literal, _type) when is_boolean(literal), do: to_string(literal)

    defp default_type(%{} = map, :map) do
      library = Application.get_env(:postgrex, :json_library, Jason)
      default = IO.iodata_to_binary(library.encode_to_iodata!(map))
      [single_quote(default)]
    end

    defp default_type({:fragment, expr}, _type),
      do: [expr]

    defp default_type(expr, type),
      do:
        raise(
          ArgumentError,
          "unknown default `#{inspect(expr)}` for type `#{inspect(type)}`. " <>
            ":default may be a string, number, boolean, list of strings, list of integers, map (when type is Map), or a fragment(...)"
        )

    defp index_expr({dir, literal}) when is_binary(literal),
      do: index_dir(dir, literal)

    defp index_expr({dir, literal}),
      do: index_dir(dir, quote_name(literal))

    defp index_expr(literal) when is_binary(literal),
      do: literal

    defp index_expr(literal),
      do: quote_name(literal)

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
        :asc_nulls_first -> [str | " ASC NULLS FIRST"]
        :asc_nulls_last -> [str | " ASC NULLS LAST"]
        :desc -> [str | " DESC"]
        :desc_nulls_first -> [str | " DESC NULLS FIRST"]
        :desc_nulls_last -> [str | " DESC NULLS LAST"]
      end
    end

    defp include_expr(literal) when is_binary(literal),
      do: literal

    defp include_expr(literal),
      do: quote_name(literal)

    defp options_expr(nil),
      do: []

    defp options_expr(keyword) when is_list(keyword),
      do: error!(nil, "PostgreSQL adapter does not support keyword lists in :options")

    defp options_expr(options),
      do: [?\s, options]

    defp column_type(type, opts) do
      type_name = column_type_name(type, opts)

      case Keyword.get(opts, :generated) do
        nil when type == :identity ->
          cleanup = fn v -> is_integer(v) and v > 0 end

          sequence =
            [Keyword.get(opts, :start_value)]
            |> Enum.filter(cleanup)
            |> Enum.map(&"START WITH #{&1}")
            |> Kernel.++(
              [Keyword.get(opts, :increment)]
              |> Enum.filter(cleanup)
              |> Enum.map(&"INCREMENT BY #{&1}")
            )

          case sequence do
            [] -> [type_name, " GENERATED BY DEFAULT AS IDENTITY"]
            _ -> [type_name, " GENERATED BY DEFAULT AS IDENTITY(", Enum.join(sequence, " "), ") "]
          end

        nil ->
          type_name

        expr when is_binary(expr) ->
          [type_name, " GENERATED ", expr]

        other ->
          raise ArgumentError,
                "the `:generated` option only accepts strings, received: #{inspect(other)}"
      end
    end

    defp column_type_name({:array, type}, opts) do
      [column_type_name(type, opts), "[]"]
    end

    defp column_type_name(type, _opts) when type in ~w(time utc_datetime naive_datetime)a do
      [ecto_to_db(type), "(0)"]
    end

    defp column_type_name(type, opts)
         when type in ~w(time_usec utc_datetime_usec naive_datetime_usec)a do
      precision = Keyword.get(opts, :precision)
      type_name = ecto_to_db(type)

      if precision do
        [type_name, ?(, to_string(precision), ?)]
      else
        type_name
      end
    end

    defp column_type_name(:duration, opts) do
      precision = Keyword.get(opts, :precision)
      fields = Keyword.get(opts, :fields)
      type_name = ecto_to_db(:duration)

      cond do
        fields && precision -> [type_name, " ", fields, ?(, to_string(precision), ?)]
        precision -> [type_name, ?(, to_string(precision), ?)]
        fields -> [type_name, " ", fields]
        true -> [type_name]
      end
    end

    defp column_type_name(type, opts) do
      size = Keyword.get(opts, :size)
      precision = Keyword.get(opts, :precision)
      scale = Keyword.get(opts, :scale)
      type_name = ecto_to_db(type)

      cond do
        size -> [type_name, ?(, to_string(size), ?)]
        precision -> [type_name, ?(, to_string(precision), ?,, to_string(scale || 0), ?)]
        type == :string -> [type_name, "(255)"]
        true -> type_name
      end
    end

    defp reference_expr(%Reference{} = ref, table, name) do
      {current_columns, reference_columns} = Enum.unzip([{name, ref.column} | ref.with])

      [
        "CONSTRAINT ",
        reference_name(ref, table, name),
        ?\s,
        "FOREIGN KEY (",
        quote_names(current_columns),
        ") REFERENCES ",
        quote_name(Keyword.get(ref.options, :prefix, table.prefix), ref.table),
        ?(,
        quote_names(reference_columns),
        ?),
        reference_match(ref.match),
        reference_on_delete(ref.on_delete),
        reference_on_update(ref.on_update),
        validate(ref.validate)
      ]
    end

    defp drop_reference_expr({%Reference{} = ref, _opts}, table, name),
      do: drop_reference_expr(ref, table, name)

    defp drop_reference_expr(%Reference{} = ref, table, name),
      do: ["DROP CONSTRAINT ", reference_name(ref, table, name), ", "]

    defp drop_reference_expr(_, _, _),
      do: []

    defp drop_reference_if_exists_expr(%Reference{} = ref, table, name),
      do: ["DROP CONSTRAINT IF EXISTS ", reference_name(ref, table, name), ", "]

    defp drop_reference_if_exists_expr(_, _, _),
      do: []

    defp reference_name(%Reference{name: nil}, table, column),
      do: quote_name("#{table.name}_#{column}_fkey")

    defp reference_name(%Reference{name: name}, _table, _column),
      do: quote_name(name)

    defp reference_column_type(:serial, _opts), do: "integer"
    defp reference_column_type(:bigserial, _opts), do: "bigint"
    defp reference_column_type(:identity, _opts), do: "bigint"
    defp reference_column_type(type, opts), do: column_type(type, opts)

    defp reference_on_delete(:nilify_all), do: " ON DELETE SET NULL"

    defp reference_on_delete({:nilify, columns}),
      do: [" ON DELETE SET NULL (", quote_names(columns), ")"]

    defp reference_on_delete(:default_all), do: " ON DELETE SET DEFAULT"

    defp reference_on_delete({:default, columns}),
      do: [" ON DELETE SET DEFAULT (", quote_names(columns), ")"]

    defp reference_on_delete(:delete_all), do: " ON DELETE CASCADE"
    defp reference_on_delete(:restrict), do: " ON DELETE RESTRICT"
    defp reference_on_delete(_), do: []

    defp reference_on_update(:nilify_all), do: " ON UPDATE SET NULL"
    defp reference_on_update(:update_all), do: " ON UPDATE CASCADE"
    defp reference_on_update(:restrict), do: " ON UPDATE RESTRICT"
    defp reference_on_update(_), do: []

    defp reference_match(nil), do: []
    defp reference_match(:full), do: " MATCH FULL"
    defp reference_match(:simple), do: " MATCH SIMPLE"
    defp reference_match(:partial), do: " MATCH PARTIAL"

    defp validate(false), do: " NOT VALID"
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

    defp quote_qualified_name(name, sources, ix) do
      {_, source, _} = elem(sources, ix)
      [source, ?. | quote_name(name)]
    end

    defp quote_names(names) do
      Enum.map_intersperse(names, ?,, &quote_name/1)
    end

    defp quote_name(nil, name), do: quote_name(name)

    defp quote_name(prefix, name), do: [quote_name(prefix), ?., quote_name(name)]

    defp quote_name(name) when is_atom(name) do
      quote_name(Atom.to_string(name))
    end

    defp quote_name(name) when is_binary(name) do
      if String.contains?(name, "\"") do
        error!(nil, "bad literal/field/index/table name #{inspect(name)} (\" is not permitted)")
      end

      [?", name, ?"]
    end

    # TRUE, ON, or 1 to enable the option, and FALSE, OFF, or 0 to disable it
    defp quote_boolean(nil), do: nil
    defp quote_boolean(true), do: "TRUE"
    defp quote_boolean(false), do: "FALSE"
    defp quote_boolean(value), do: error!(nil, "bad boolean value #{value}")

    defp format_to_sql(:text), do: "FORMAT TEXT"
    defp format_to_sql(:map), do: "FORMAT JSON"
    defp format_to_sql(:yaml), do: "FORMAT YAML"

    defp single_quote(value), do: [?', escape_string(value), ?']

    defp bitstring_literal(value) do
      size = bit_size(value)
      <<val::size(size)>> = value

      [?b, ?', val |> Integer.to_string(2) |> String.pad_leading(size, ["0"]), ?']
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
      :binary.replace(value, "'", "''", [:global])
    end

    defp escape_json(value) when is_binary(value) do
      escaped =
        value
        |> escape_string()
        |> :binary.replace("\"", "\\\"", [:global])

      [?", escaped, ?"]
    end

    defp escape_json(value) when is_integer(value) do
      Integer.to_string(value)
    end

    defp escape_json(true), do: ["true"]
    defp escape_json(false), do: ["false"]

    # To allow columns in json paths, we use the array[...] syntax
    # which requires special handling for strings and column references.
    # We still keep the escape_json/1 variant for strings because it is
    # needed for the queries using @>
    defp escape_json(value, _, _) when is_binary(value) do
      [?', escape_string(value), ?']
    end

    defp escape_json({{:., _, [{:&, _, [_]}, _]}, _, []} = expr, sources, query) do
      expr(expr, sources, query)
    end

    defp escape_json({{:., _, [{:parent_as, _, [_]}, _]}, _, []} = expr, sources, query) do
      expr(expr, sources, query)
    end

    defp escape_json(other, _, _) do
      escape_json(other)
    end

    defp ecto_to_db({:array, t}), do: [ecto_to_db(t), ?[, ?]]
    defp ecto_to_db(:id), do: "integer"
    defp ecto_to_db(:identity), do: "bigint"
    defp ecto_to_db(:serial), do: "serial"
    defp ecto_to_db(:bigserial), do: "bigserial"
    defp ecto_to_db(:binary_id), do: "uuid"
    defp ecto_to_db(:string), do: "varchar"
    defp ecto_to_db(:bitstring), do: "varbit"
    defp ecto_to_db(:binary), do: "bytea"
    defp ecto_to_db(:map), do: Application.fetch_env!(:ecto_sql, :postgres_map_type)
    defp ecto_to_db({:map, _}), do: Application.fetch_env!(:ecto_sql, :postgres_map_type)
    defp ecto_to_db(:time_usec), do: "time"
    defp ecto_to_db(:utc_datetime), do: "timestamp"
    defp ecto_to_db(:utc_datetime_usec), do: "timestamp"
    defp ecto_to_db(:naive_datetime), do: "timestamp"
    defp ecto_to_db(:naive_datetime_usec), do: "timestamp"
    defp ecto_to_db(:duration), do: "interval"
    defp ecto_to_db(atom) when is_atom(atom), do: Atom.to_string(atom)

    defp ecto_to_db(type) do
      raise ArgumentError,
            "unsupported type `#{inspect(type)}`. The type can either be an atom, a string " <>
              "or a tuple of the form `{:map, t}` or `{:array, t}` where `t` itself follows the same conditions."
    end

    defp error!(nil, message) do
      raise ArgumentError, message
    end

    defp error!(query, message) do
      raise Ecto.QueryError, query: query, message: message
    end
  end
end
