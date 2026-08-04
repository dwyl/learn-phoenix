defmodule NimblePool.MixProject do
  use Mix.Project

  @version "1.1.0"
  @url "https://github.com/dashbitco/nimble_pool"

  def project do
    [
      app: :nimble_pool,
      version: @version,
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      name: "NimblePool",
      description: "A tiny resource-pool implementation",
      deps: deps(),
      docs: docs(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: ["coveralls.html": :test]
    ]
  end

  def application do
    [
      mod: {NimblePool.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.21", only: :docs},
      {:excoveralls, "~> 0.16.1", only: :test}
    ]
  end

  defp docs do
    [
      main: "NimblePool",
      source_ref: "v#{@version}",
      source_url: @url,
      groups_for_functions: [
        "Worker callbacks": &(&1[:callback] == :worker),
        "Pool callbacks": &(&1[:callback] == :pool)
      ]
    ]
  end

  defp package do
    %{
      licenses: ["Apache-2.0"],
      maintainers: ["José Valim"],
      links: %{"GitHub" => @url}
    }
  end
end
