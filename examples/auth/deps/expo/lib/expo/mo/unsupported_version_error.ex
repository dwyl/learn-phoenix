defmodule Expo.MO.UnsupportedVersionError do
  @moduledoc """
  An error returned when the version of the MO file is not supported.

  All the fields in this struct are public.
  """

  @type t :: %__MODULE__{
          major: non_neg_integer,
          minor: non_neg_integer,
          file: Path.t() | nil
        }

  defexception [:major, :minor, :file]

  @impl Exception
  def message(%__MODULE__{major: major, minor: minor, file: file}) do
    prefix = if file, do: "#{Path.relative_to_cwd(file)}: ", else: ""
    "#{prefix}invalid version, only ~> 0.0 is supported, #{major}.#{minor} given"
  end
end
