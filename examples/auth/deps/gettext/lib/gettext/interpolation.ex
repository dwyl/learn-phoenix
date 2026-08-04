defmodule Gettext.Interpolation do
  @moduledoc """
  Behaviour to provide Gettext string interpolation.

  By default, Gettext uses `Gettext.Interpolation.Default` as the interpolation module.
  """

  @typedoc since: "0.19.0"
  @type translation_type() :: :translation | :plural_translation

  @typedoc since: "0.22.0"
  @type bindings() :: %{optional(atom()) => term()}

  @doc """
  Called to perform interpolation *at runtime*.

  If successful, should return `{:ok, interpolated_string}`. If there
  are missing bindings, should return `{:missing_bindings, partially_interpolated, missing}`
  where `partially_interpolated` is a string with the available bindings interpolated.
  """
  @doc since: "0.19.0"
  @callback runtime_interpolate(message :: String.t(), bindings()) ::
              {:ok, String.t()}
              | {:missing_bindings, partially_interpolated_message :: String.t(),
                 missing_bindings :: [atom()]}

  @doc """
  Called to perform interpolation *at compile time*.
  """
  @doc since: "0.19.0"
  @macrocallback compile_interpolate(translation_type(), message :: String.t(), bindings()) ::
                   Macro.t()

  @doc """
  Defines the Gettext message format to be used when extracting.

  The default interpolation module that ships with Gettext uses `"elixir-format"`.

  See the [GNU Gettext
  documentation](https://www.gnu.org/software/gettext/manual/html_node/PO-Files.html#index-msgstr).
  """
  @doc since: "0.19.0"
  @callback message_format() :: String.t()
end
