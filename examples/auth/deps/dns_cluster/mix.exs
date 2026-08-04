defmodule DNSCluster.MixProject do
  use Mix.Project

  @version "0.2.0"
  @scm_url "https://github.com/phoenixframework/dns_cluster"

  def project do
    [
      app: :dns_cluster,
      package: package(),
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @scm_url,
      homepage_url: @scm_url,
      description: "Simple DNS clustering for distributed Elixir nodes"
    ]
  end

  defp package do
    [
      maintainers: ["Chris McCord"],
      licenses: ["MIT"],
      links: %{"GitHub" => @scm_url},
      files: ~w(lib CHANGELOG.md LICENSE.md mix.exs README.md .formatter.exs)
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [{:ex_doc, ">= 0.0.0", only: :docs}]
  end
end
