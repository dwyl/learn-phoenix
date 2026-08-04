defmodule ElixirMake.Mixfile do
  use Mix.Project

  @version "0.9.0"
  def project do
    [
      app: :elixir_make,
      version: @version,
      elixir: "~> 1.9",
      description: "A Make compiler for Mix",
      package: package(),
      docs: docs(),
      deps: deps(),
      xref: [exclude: [Mix, :crypto, :ssl, :public_key, :httpc]]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.20", only: :docs}
    ]
  end

  defp package do
    %{
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/elixir-lang/elixir_make"},
      maintainers: ["Andrea Leopardi", "José Valim"]
    }
  end

  defp docs do
    [
      main: "Mix.Tasks.Compile.ElixirMake",
      extras: ["PRECOMPILATION_GUIDE.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: "https://github.com/elixir-lang/elixir_make"
    ]
  end
end
