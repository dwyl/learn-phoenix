defmodule Mix.Tasks.Swoosh.Mailbox.Server do
  @moduledoc """
  Starts the mailbox preview server.

  ## Command line options

  This task accepts the same command-line arguments as `run`.
  For additional information, refer to the documentation for `Mix.Tasks.Run`.

  For example, to run `swoosh.mailbox.server` without checking dependencies:

      mix swoosh.mailbox.server --no-deps-check

  The `--no-halt` flag is automatically added.
  """

  use Mix.Task

  @shortdoc "Starts the mailbox preview server"

  def run(args) do
    Application.put_env(:swoosh, :serve_mailbox, true)
    Mix.Task.run("run", run_args() ++ args)
  end

  defp run_args do
    if iex_running?(), do: [], else: ["--no-halt"]
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) && IEx.started?()
  end
end
