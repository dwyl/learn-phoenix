defmodule Ecto.Adapter.Structure do
  @moduledoc """
  Specifies the adapter structure (dump/load) API.
  """

  @doc """
  Dumps the given structure.

  The path will be looked in the `config` under :dump_path or
  default to the structure path inside `default`.

  Returns an `:ok` tuple if it was dumped successfully, an error tuple otherwise.

  ## Examples

      structure_dump("priv/repo", username: "postgres",
                                  database: "ecto_test",
                                  hostname: "localhost")

  """
  @callback structure_dump(default :: String.t(), config :: Keyword.t()) ::
              {:ok, String.t()} | {:error, term}

  @doc """
  Loads the given structure.

  The path will be looked in the `config` under :dump_path or
  default to the structure path inside `default`.

  Returns an `:ok` tuple if it was loaded successfully, an error tuple otherwise.

  ## Examples

      structure_load("priv/repo", username: "postgres",
                                  database: "ecto_test",
                                  hostname: "localhost")

  """
  @callback structure_load(default :: String.t(), config :: Keyword.t()) ::
              {:ok, String.t()} | {:error, term}

  @doc """
  Runs the dump command for the given repo / config.

  Calling this function will setup authentication and run the dump cli
  command with your provided `args`.

  The options in `opts` are passed directly to `System.cmd/3`.

  Returns `{output, exit_status}` where `output` is a string of the stdout
  (as long as no option `into` is provided, see `System.cmd/3`) and `exit_status`
  is the exit status of the invocation. (`0` for success)

  ## Examples

      iex> dump_cmd(["--data-only", "--table", "table_name"], [stdout_to_stderr: true], Acme.Repo.config())
      {"--\n-- PostgreSQL database dump\n--\n" <> _rest, 0}

  """
  @callback dump_cmd(args :: [String.t()], opts :: Keyword.t(), config :: Keyword.t()) ::
              {output :: Collectable.t(), exit_status :: non_neg_integer()}
end
