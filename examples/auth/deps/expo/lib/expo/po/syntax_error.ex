defmodule Expo.PO.SyntaxError do
  @moduledoc """
  An error raised when the syntax in a PO file (a file ending in `.po`) isn't
  correct.
  """

  @type t :: %__MODULE__{
          file: Path.t() | nil,
          line: pos_integer,
          reason: String.t()
        }

  defexception [:file, :line, :reason]

  @impl Exception
  def message(%__MODULE__{file: file, line: line, reason: reason}) do
    if file, do: "#{Path.relative_to_cwd(file)}:#{line}: #{reason}", else: "#{line}: #{reason}"
  end
end
