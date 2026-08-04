defmodule Expo.MO.InvalidFileError do
  @moduledoc """
  An error raised when the content does not follow the MO file structure.

  The fields of this exception are public.
  """

  @type t :: %__MODULE__{
          file: Path.t() | nil
        }

  defexception [:file]

  @impl Exception
  def message(%__MODULE__{file: file}) do
    prefix = if file, do: "#{Path.relative_to_cwd(file)}: ", else: ""
    "#{prefix}invalid file"
  end
end
