defmodule Expo.PluralForms.SyntaxError do
  @moduledoc """
  An error raised when the syntax in a plural forms string is invalid.
  """

  @type t() :: %__MODULE__{
          line: pos_integer(),
          column: pos_integer() | nil,
          reason: String.t()
        }

  defexception [:line, :column, :reason]

  @impl Exception
  def message(%__MODULE__{line: line, column: column, reason: reason}) do
    prefix = if column, do: "#{line}:#{column}", else: "#{line}"
    "#{prefix}: #{reason}"
  end
end
