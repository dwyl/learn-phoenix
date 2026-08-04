defmodule LazyHTML.MixProject do
  use Mix.Project

  # v2.5.0 + :lexbor-contains() feature
  @lexbor_git_sha "244b84956a6dc7eec293781d051354f351274c46"

  @version "0.1.7"
  @description "Efficient parsing and querying of HTML documents"
  @github_url "https://github.com/dashbitco/lazy_html"

  def project do
    [
      app: :lazy_html,
      version: @version,
      name: "LazyHTML",
      description: @description,
      elixir: "~> 1.15",
      compilers: [:elixir_make] ++ Mix.compilers(),
      deps: deps(),
      docs: docs(),
      package: package(),
      make_env: fn ->
        %{
          "FINE_INCLUDE_DIR" => Fine.include_dir(),
          "LEXBOR_GIT_SHA" => @lexbor_git_sha
        }
      end,
      # Precompilation
      make_precompiler: {:nif, CCPrecompiler},
      make_precompiler_url: "#{@github_url}/releases/download/v#{@version}/@{artefact_filename}",
      make_precompiler_filename: "liblazy_html",
      make_precompiler_nif_versions: [versions: ["2.16"]]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:fine, "~> 0.1.0"},
      {:elixir_make, "~> 0.9.0"},
      {:cc_precompiler, "~> 0.1", runtime: false},
      {:ex_doc, "~> 0.36", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "LazyHTML",
      source_url: @github_url,
      source_ref: "v#{@version}"
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @github_url},
      files:
        ~w(c_src lib config mix.exs README.md LICENSE CHANGELOG.md Makefile Makefile.win checksum.exs)
    ]
  end
end
