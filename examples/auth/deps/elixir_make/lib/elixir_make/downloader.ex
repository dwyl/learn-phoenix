defmodule ElixirMake.Downloader do
  @moduledoc """
  The behaviour for downloader modules.
  """

  @doc """
  This callback should download the artefact from the given URL.
  """
  @callback download(url :: String.t()) :: {:ok, iolist() | binary()} | {:error, String.t()}
end
