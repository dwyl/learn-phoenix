defmodule PhoenixLiveReload.Mixfile do
  use Mix.Project

  @version "1.6.1"

  def project do
    [
      app: :phoenix_live_reload,
      version: @version,
      elixir: "~> 1.11",
      deps: deps(),

      # Hex
      description: "Provides live-reload functionality for Phoenix",
      package: package(),

      # Docs
      name: "Phoenix Live-Reload",
      docs: docs()
    ]
  end

  defp package do
    [
      maintainers: ["Chris McCord", "José Valim"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/phoenixframework/phoenix_live_reload"}
    ]
  end

  def application do
    [
      mod: {Phoenix.LiveReloader.Application, []},
      extra_applications: [:logger, :phoenix, :file_system]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.4"},
      {:ex_doc, "~> 0.29", only: :docs},
      {:makeup_eex, ">= 0.1.1", only: :docs},
      {:makeup_diff, "~> 0.1", only: :docs},
      {:file_system, "~> 0.2.10 or ~> 1.0"},
      {:jason, "~> 1.0", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      source_ref: "v#{@version}",
      source_url: "https://github.com/phoenixframework/phoenix_live_reload"
    ]
  end
end
