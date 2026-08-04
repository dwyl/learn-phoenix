defmodule EctoSQL.MixProject do
  use Mix.Project

  @source_url "https://github.com/elixir-ecto/ecto_sql"
  @version "3.13.2"
  @adapters ~w(pg myxql tds)

  def project do
    [
      app: :ecto_sql,
      version: @version,
      elixir: "~> 1.14",
      deps: deps(),
      test_paths: test_paths(System.get_env("ECTO_ADAPTER")),
      xref: [
        exclude: [
          MyXQL,
          Ecto.Adapters.MyXQL.Connection,
          Postgrex,
          Ecto.Adapters.Postgres.Connection,
          Tds,
          Tds.Ecto.UUID,
          Ecto.Adapters.Tds.Connection
        ]
      ],

      # Custom testing
      aliases: [
        "test.all": ["test", "test.adapters", "test.as_a_dep"],
        "test.adapters": &test_adapters/1,
        "test.as_a_dep": &test_as_a_dep/1
      ],
      preferred_cli_env: ["test.all": :test, "test.adapters": :test],

      # Hex
      description: "SQL-based adapters for Ecto and database migrations",
      package: package(),

      # Docs
      name: "Ecto SQL",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :eex],
      env: [postgres_map_type: "jsonb"],
      mod: {Ecto.Adapters.SQL.Application, []}
    ]
  end

  defp deps do
    [
      ecto_dep(),
      {:telemetry, "~> 0.4.0 or ~> 1.0"},

      # Drivers
      {:db_connection, "~> 2.5 or ~> 2.4.1"},
      postgrex_dep(),
      myxql_dep(),
      tds_dep(),

      # Bring something in for JSON during tests
      {:jason, ">= 0.0.0", only: [:test, :docs]},

      # Docs
      {:ex_doc, "~> 0.21", only: :docs},

      # Benchmarks
      {:benchee, "~> 1.0", only: :bench}
    ]
  end

  defp ecto_dep do
    if path = System.get_env("ECTO_PATH") do
      {:ecto, path: path}
    else
      {:ecto, "~> 3.13.0"}
    end
  end

  defp postgrex_dep do
    if path = System.get_env("POSTGREX_PATH") do
      {:postgrex, path: path}
    else
      {:postgrex, "~> 0.19 or ~> 1.0", optional: true}
    end
  end

  defp myxql_dep do
    if path = System.get_env("MYXQL_PATH") do
      {:myxql, path: path}
    else
      {:myxql, "~> 0.7", optional: true}
    end
  end

  defp tds_dep do
    if path = System.get_env("TDS_PATH") do
      {:tds, path: path}
    else
      {:tds, "~> 2.1.1 or ~> 2.2", optional: true}
    end
  end

  defp test_paths(adapter) when adapter in @adapters, do: ["integration_test/#{adapter}"]
  defp test_paths(nil), do: ["test"]
  defp test_paths(other), do: raise("unknown adapter #{inspect(other)}")

  defp package do
    [
      maintainers: ["Eric Meadows-Jönsson", "José Valim", "James Fish", "Michał Muskała"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files:
        ~w(.formatter.exs mix.exs README.md CHANGELOG.md lib) ++
          ~w(integration_test/sql integration_test/support)
    ]
  end

  defp test_as_a_dep(args) do
    IO.puts("==> Compiling ecto_sql from a dependency")
    File.rm_rf!("tmp/as_a_dep")
    File.mkdir_p!("tmp/as_a_dep")

    File.cd!("tmp/as_a_dep", fn ->
      File.write!("mix.exs", """
      defmodule DepsOnEctoSQL.MixProject do
        use Mix.Project

        def project do
          [
            app: :deps_on_ecto_sql,
            version: "0.0.1",
            deps: [{:ecto_sql, path: "../.."}]
          ]
        end
      end
      """)

      mix_cmd_with_status_check(["do", "deps.get,", "compile", "--force" | args])
    end)
  end

  defp test_adapters(args) do
    for adapter <- @adapters, do: env_run(adapter, args)
  end

  defp env_run(adapter, args) do
    IO.puts("==> Running tests for ECTO_ADAPTER=#{adapter} mix test")

    mix_cmd_with_status_check(
      ["test", ansi_option() | args],
      env: [{"ECTO_ADAPTER", adapter}]
    )
  end

  defp ansi_option do
    if IO.ANSI.enabled?(), do: "--color", else: "--no-color"
  end

  defp mix_cmd_with_status_check(args, opts \\ []) do
    {_, res} = System.cmd("mix", args, [into: IO.binstream(:stdio, :line)] ++ opts)

    if res > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  defp docs do
    [
      main: "Ecto.Adapters.SQL",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/ecto_sql",
      source_url: @source_url,
      extras: ["CHANGELOG.md"],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      groups_for_modules: [
        # Ecto.Adapters.SQL,
        # Ecto.Adapters.SQL.Sandbox,
        # Ecto.Migration,
        # Ecto.Migrator,

        "Built-in adapters": [
          Ecto.Adapters.MyXQL,
          Ecto.Adapters.Tds,
          Ecto.Adapters.Postgres
        ],
        "TDS Types": [
          Tds.Ecto.UUID,
          Tds.Ecto.VarChar
        ],
        "Adapter specification": [
          Ecto.Adapter.Migration,
          Ecto.Adapter.Structure,
          Ecto.Adapters.SQL.Connection,
          Ecto.Migration.Command,
          Ecto.Migration.Constraint,
          Ecto.Migration.Index,
          Ecto.Migration.Reference,
          Ecto.Migration.Table
        ]
      ]
    ]
  end
end
