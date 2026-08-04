defmodule CCPrecompiler.CompilationScript do
  @callback compile(
              app :: atom(),
              version :: String.t(),
              nif_version :: String.t(),
              target :: String.t(),
              command_line_args :: [String.t()],
              custom_args :: [String.t()]
            ) :: :ok | {:error, String.t()}
end
