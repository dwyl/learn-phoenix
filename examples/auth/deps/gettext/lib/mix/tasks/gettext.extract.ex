defmodule Mix.Tasks.Gettext.Extract do
  use Mix.Task
  @recursive true

  @shortdoc "Extracts messages from source code"

  @moduledoc """
  Extracts messages by recompiling the Elixir source code.

  ```bash
  mix gettext.extract [OPTIONS]
  ```

  messages are extracted into POT (Portable Object Template) files with a
  `.pot` extension. The location of these files is determined by the `:otp_app`
  and `:priv` options given by Gettext modules when they call `use Gettext`. One
  POT file is generated for each message domain.

  All automatically-extracted messages are assigned the `elixir-autogen` flag.
  If a message from the POT is no longer present and has the `elixir-autogen`
  flag, the message is removed.

  Before `v0.19.0`, the `elixir-format` flag was used to detect automatically
  extracted messages. This has been deprecated in `v0.19.0`. When extracting
  with the newest version, the new `elixir-autogen` flag is added to all
  automatically extracted messages.

  All messages are assigned a format flag. When using the default
  interpolation module, that flag is `elixir-format`. With other interpolation
  modules, the flag name is defined by that implementation (see
  `c:Gettext.Interpolation.message_format/0`).

  If you would like to verify that your POT files are up to date with the
  current state of the codebase, you can provide the `--check-up-to-date`
  flag. This is particularly useful for automated checks and in CI systems.
  This validation will fail even when the same calls to Gettext
  only change location in the codebase:

  ```bash
  mix gettext.extract --check-up-to-date
  ```

  It is possible to pass the `--merge` option to perform merging
  for every Gettext backend updated during merge:

  ```bash
  mix gettext.extract --merge
  ```

  All other options passed to `gettext.extract` are forwarded to the
  `gettext.merge` task (`Mix.Tasks.Gettext.Merge`), which is called internally
  by this task. For example:

  ```bash
  mix gettext.extract --merge --no-fuzzy
  ```

  """

  @switches [merge: :boolean, check_up_to_date: :boolean]

  @impl true
  def run(args) do
    Application.ensure_all_started(:gettext)
    _ = Mix.Project.get!()
    mix_config = Mix.Project.config()
    {opts, _} = OptionParser.parse!(args, switches: @switches)
    pot_files = extract(mix_config[:app], mix_config[:gettext] || [])

    if opts[:check_up_to_date] do
      run_up_to_date_check(pot_files)
    else
      run_message_extraction(pot_files, opts, args)
    end
  end

  defp run_message_extraction(pot_files, opts, args) do
    for {path, {:changed, contents}} <- pot_files do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
      Mix.shell().info("Extracted #{Path.relative_to_cwd(path)}")
    end

    if opts[:merge] do
      run_merge(pot_files, args)
    end

    :ok
  end

  defp run_up_to_date_check(pot_files) do
    not_extracted_paths = for {path, {:changed, _contents}} <- pot_files, do: path

    if not_extracted_paths == [] do
      :ok
    else
      Mix.raise("""
      mix gettext.extract failed due to --check-up-to-date.
      The following POT files were not extracted or are out of date:

      #{Enum.map_join(not_extracted_paths, "\n", &"  * #{&1 |> Path.relative_to_cwd()}")}
      """)
    end
  end

  defp extract(app, gettext_config) do
    Gettext.Extractor.enable()
    force_compile()
    Gettext.Extractor.pot_files(app, gettext_config)
  after
    Gettext.Extractor.disable()
  end

  defp force_compile do
    Mix.Tasks.Compile.Elixir.clean()
    Enum.each(Mix.Tasks.Compile.Elixir.manifests(), &File.rm/1)

    # If "compile" was never called, the reenabling is a no-op and
    # "compile.elixir" is a no-op as well (because it wasn't reenabled after
    # running "compile"). If "compile" was already called, then running
    # "compile" is a no-op and running "compile.elixir" will work because we
    # manually reenabled it.
    Mix.Task.reenable("compile.elixir")
    Mix.Task.run("compile")
    Mix.Task.run("compile.elixir", ["--force"])
  end

  defp run_merge(pot_files, argv) do
    pot_files
    |> Enum.map(fn {path, _} -> Path.dirname(path) end)
    |> Enum.uniq()
    |> Task.async_stream(&Mix.Tasks.Gettext.Merge.run([&1 | argv]), ordered: false)
    |> Stream.run()
  end
end
