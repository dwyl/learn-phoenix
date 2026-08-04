defmodule CCPrecompiler.MixProject do
  use Mix.Project

  @app :cc_precompiler
  @version "0.1.11"
  @github_url "https://github.com/cocoa-xu/cc_precompiler"
  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: "NIF library Precompiler that uses C/C++ (cross-)compiler.",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :eex]
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.7 or ~> 0.8 or ~> 0.9", runtime: false},
      # docs
      {:ex_doc, ">= 0.0.0", only: :docs, runtime: false}
    ]
  end

  defp package do
    [
      name: Atom.to_string(@app),
      files: ~w(lib mix.exs README* LICENSE* *.md),
      licenses: ["Apache-2.0"],
      links: links()
    ]
  end

  defp docs do
    [
      main: "PRECOMPILATION_GUIDE",
      source_ref: "v#{@version}",
      source_url: @github_url,
      extras: [
        "PRECOMPILATION_GUIDE.md",
        "CHANGELOG.md"
      ]
    ]
  end

  defp links do
    %{
      "GitHub" => @github_url,
      "Readme" => "#{@github_url}/blob/v#{@version}/README.md",
      "Precompilation Guide" => "#{@github_url}/blob/v#{@version}/PRECOMPILATION_GUIDE.md",
      "Changelog" => "#{@github_url}/blob/v#{@version}/CHANGELOG.md"
    }
  end
end
