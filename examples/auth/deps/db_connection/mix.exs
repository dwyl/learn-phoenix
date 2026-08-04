defmodule DBConnection.Mixfile do
  use Mix.Project

  @source_url "https://github.com/elixir-ecto/db_connection"
  @pools [:connection_pool, :ownership]
  @version "2.8.1"

  def project do
    [
      app: :db_connection,
      version: @version,
      elixir: "~> 1.11",
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      build_per_environment: false,
      consolidate_protocols: false,
      test_paths: test_paths(Mix.env()),
      aliases: ["test.all": ["test", "test.pools"], "test.pools": &test_pools/1],
      preferred_cli_env: ["test.all": :test]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {DBConnection.App, []}
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:telemetry, "~> 0.4 or ~> 1.0"}
    ]
  end

  defp docs do
    [
      source_url: @source_url,
      source_ref: "v#{@version}",
      main: DBConnection,
      extras: ["CHANGELOG.md"]
    ]
  end

  defp description do
    """
    Database connection behaviour for database transactions and connection pooling
    """
  end

  defp package do
    %{
      licenses: ["Apache-2.0"],
      maintainers: ["James Fish", "José Valim"],
      links: %{"GitHub" => @source_url}
    }
  end

  defp test_paths(pool) when pool in @pools, do: ["integration_test/#{pool}"]
  defp test_paths(_), do: ["test"]

  defp test_pools(args) do
    for env <- @pools, do: env_run(env, args)
  end

  defp env_run(env, args) do
    args = if IO.ANSI.enabled?(), do: ["--color" | args], else: ["--no-color" | args]

    IO.puts("==> Running tests for MIX_ENV=#{env} mix test")

    {_, res} =
      System.cmd("mix", ["test" | args],
        into: IO.binstream(:stdio, :line),
        env: [{"MIX_ENV", to_string(env)}]
      )

    if res > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end
end
