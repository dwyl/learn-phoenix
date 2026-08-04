defmodule Fine.MixProject do
  use Mix.Project

  @version "0.1.4"
  @description "C++ library enabling more ergonomic NIFs, tailored to Elixir"
  @github_url "https://github.com/elixir-nx/fine"

  def project do
    [
      app: :fine,
      version: @version,
      elixir: "~> 1.15",
      name: "Fine",
      description: @description,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: docs(),
      package: package()
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:ex_doc, "~> 0.37", only: :dev, runtime: false},
      {:makeup_syntect, "~> 0.1", only: :dev, runtime: false}
    ]
  end

  defp aliases() do
    [test: fn _ -> Mix.shell().error("To run tests, go to the test directory") end]
  end

  defp docs() do
    [
      main: "Fine",
      source_url: @github_url,
      source_ref: "v#{@version}"
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @github_url},
      files: ~w(c_include lib mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end
end
