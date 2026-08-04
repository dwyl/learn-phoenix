defmodule Gettext.Mixfile do
  use Mix.Project

  @version "0.26.2"

  @description "Internationalization and localization through gettext"
  @repo_url "https://github.com/elixir-gettext/gettext"

  def project do
    [
      app: :gettext,
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      deps: deps(),
      preferred_cli_env: [coveralls: :test, "coveralls.html": :test, "coveralls.github": :test],
      test_coverage: [tool: ExCoveralls],

      # Hex
      package: hex_package(),
      description: @description,

      # Docs
      name: "gettext",
      docs: [
        source_ref: "v#{@version}",
        main: "Gettext",
        source_url: @repo_url,
        extras: ["CHANGELOG.md"],
        groups_for_docs: [
          # Gettext
          "Translation Functions": &(&1[:section] == :translation),
          "Locale Functions": &(&1[:section] == :locale),

          # Gettext.Macros
          "Macros with Backend":
            &(&1[:module] == Gettext.Macros and to_string(&1[:name]) =~ ~r/_with_backend$/),
          "Comment Macros": &(&1[:module] == Gettext.Macros and &1[:name] == :gettext_comment),
          "Extraction Macros":
            &(&1[:module] == Gettext.Macros and to_string(&1[:name]) =~ ~r/_noop$/),
          "Translation Macros": &(&1[:module] == Gettext.Macros)
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      env: [default_locale: "en", plural_forms: Gettext.Plural],
      mod: {Gettext.Application, []}
    ]
  end

  def hex_package do
    [
      maintainers: ["Andrea Leopardi", "Jonatan Männchen", "José Valim"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @repo_url,
        "Changelog" => @repo_url <> "/blob/main/CHANGELOG.md"
      },
      files: ~w(lib mix.exs *.md)
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_other), do: ["lib"]

  defp deps do
    [
      {:expo, "~> 0.5.1 or ~> 1.0"},

      # Dev and test dependencies
      {:castore, "~> 1.0", only: :test},
      {:jason, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.19", only: :dev},
      {:excoveralls, "~> 0.18.0", only: :test}
    ]
  end
end
