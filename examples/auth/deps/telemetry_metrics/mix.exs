defmodule Telemetry.Metrics.MixProject do
  use Mix.Project

  @version "1.1.0"

  def project do
    [
      name: "Telemetry.Metrics",
      app: :telemetry_metrics,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      preferred_cli_env: preferred_cli_env(),
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp preferred_cli_env do
    [
      docs: :docs,
      dialyzer: :test,
      "coveralls.json": :test
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 0.4 or ~> 1.0"},
      {:ex_doc, "~> 0.20", only: :docs},
      {:dialyxir, "~> 1.0", only: :test, runtime: false},
      {:excoveralls, "~> 0.14.0", only: :test, runtime: false}
    ]
  end

  defp docs do
    [
      main: "Telemetry.Metrics",
      canonical: "http://hexdocs.pm/telemetry_metrics",
      source_url: "https://github.com/beam-telemetry/telemetry_metrics",
      source_ref: "v#{@version}",
      extras: [
        "docs/rationale.md",
        "docs/writing_reporters.md"
      ],
      groups_for_modules: [
        # Telemetry.Metrics,

        "Metrics Structs": [
          Telemetry.Metrics.Counter,
          Telemetry.Metrics.Distribution,
          Telemetry.Metrics.LastValue,
          Telemetry.Metrics.Sum,
          Telemetry.Metrics.Summary
        ]
      ]
    ]
  end

  def description do
    """
    Provides a common interface for defining metrics based on Telemetry events.
    """
  end

  defp package do
    [
      maintainers: ["Arkadiusz Gil", "José Valim"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/beam-telemetry/telemetry_metrics"}
    ]
  end
end
