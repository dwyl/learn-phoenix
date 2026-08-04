defmodule BcryptElixir.Mixfile do
  use Mix.Project

  @source_url "https://github.com/riverrun/bcrypt_elixir"
  @version "3.3.2"
  @description "Bcrypt password hashing algorithm for Elixir"

  def project do
    [
      app: :bcrypt_elixir,
      version: @version,
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],
      description: @description,
      package: package(),
      source_url: @source_url,
      deps: deps(),
      docs: docs(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:comeonin, "~> 5.3"},
      {:elixir_make, "~> 0.6", runtime: false},
      {:ex_doc, "~> 0.23", only: :dev, runtime: false},
      {:dialyxir, "~> 1.3", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["CHANGELOG.md", "README.md"]
    ]
  end

  defp package do
    [
      files: ["lib", "c_src", "mix.exs", "Makefile*", "README.md", "LICENSE"],
      maintainers: ["David Whitlock"],
      licenses: ["BSD-3-Clause", "ISC", "BSD-4-Clause"],
      links: %{
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md",
        "GitHub" => @source_url
      }
    ]
  end
end
