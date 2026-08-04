defmodule NimbleOptions.MixProject do
  use Mix.Project

  @version "1.1.1"
  @repo_url "https://github.com/dashbitco/nimble_options"

  def project do
    [
      app: :nimble_options,
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Tests
      test_coverage: [tool: ExCoveralls],

      # Hex
      package: package(),
      description: "A tiny library for validating and documenting high-level options",

      # Docs
      name: "NimbleOptions",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: []
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # excoverals uses CAStore to push results via HTTP.
      {:castore, "~> 1.0.0", only: :test},
      {:ex_doc, ">= 0.19.0", only: :dev},
      {:excoveralls, "~> 0.18.0", only: :test}
    ]
  end

  defp package do
    [
      maintainers: ["Andrea Leopardi", "José Valim", "Marlus Saraiva"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @repo_url}
    ]
  end

  defp docs do
    [
      main: "NimbleOptions",
      extras: [
        "CHANGELOG.md": [title: "Changelog"],
        "LICENSE.md": [title: "License"]
      ],
      source_ref: "v#{@version}",
      source_url: @repo_url,
      formatters: ["html"],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
