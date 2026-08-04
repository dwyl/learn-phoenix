defmodule Gettext.Error do
  @moduledoc """
  A generic error raised for a variety of possible Gettext-related reasons.
  """

  @typedoc since: "0.22.0"
  @type t() :: %__MODULE__{}

  defexception [:message]
end
