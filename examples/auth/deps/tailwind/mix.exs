defmodule Tailwind.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/phoenixframework/tailwind"

  def project do
    [
      app: :tailwind,
      version: @version,
      elixir: "~> 1.14",
      deps: deps(),
      description: "Mix tasks for installing and invoking tailwind",
      package: [
        links: %{
          "GitHub" => @source_url,
          "tailwind" => "https://tailwindcss.com"
        },
        licenses: ["MIT"]
      ],
      docs: [
        main: "Tailwind",
        source_url: @source_url,
        source_ref: "v#{@version}",
        extras: ["CHANGELOG.md"]
      ],
      aliases: [test: ["tailwind.install --if-missing", "test"]]
    ]
  end

  def application do
    [
      extra_applications: [:logger, inets: :optional, ssl: :optional],
      mod: {Tailwind, []},
      env: [default: []]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :docs}
    ]
  end
end
