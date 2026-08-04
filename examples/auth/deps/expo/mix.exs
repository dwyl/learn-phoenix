# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Expo.MixProject do
  use Mix.Project

  @version "1.1.0"
  @source_url "https://github.com/elixir-gettext/expo"
  @description "Low-level Gettext file handling (.po/.pot/.mo file writer and parser)."

  def project do
    [
      app: :expo,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      compilers: [:yecc] ++ Mix.compilers(),
      deps: deps(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      description: @description,
      dialyzer:
        [list_unused_filters: true, plt_add_apps: [:mix]] ++
          if (System.get_env("DIALYZER_PLT_PRIV") || "false") in ["1", "true"] do
            [plt_file: {:no_warn, "priv/plts/dialyzer.plt"}]
          else
            []
          end,
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.post": :test,
        "coveralls.xml": :test
      ],
      package: package(),
      yecc_options: if(Mix.env() in [:dev, :test], do: [verbose: true])
    ]
  end

  defp package do
    %{
      licenses: ["Apache-2.0"],
      maintainers: ["Jonatan Männchen", "José Valim", "Andrea Leopardi"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @source_url <> "/blob/main/CHANGELOG.md",
        "Issues" => @source_url <> "/issues"
      }
    }
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp docs do
    [
      source_url: @source_url,
      source_ref: "v" <> @version,
      main: "readme",
      extras: ["README.md"]
    ]
  end

  defp deps do
    [
      # Dev/test dependencies
      {:credo, "~> 1.7", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.17", only: [:test], runtime: false}
    ]
  end
end
