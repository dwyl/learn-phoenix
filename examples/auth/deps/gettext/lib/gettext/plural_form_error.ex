defmodule Gettext.PluralFormError do
  @moduledoc """
  An generic error for when a plural form is missing for a given locale.
  """

  @enforce_keys [:form, :locale, :file, :line]
  defexception [:form, :locale, :file, :line]

  @type t() :: %__MODULE__{
          form: non_neg_integer(),
          locale: String.t(),
          file: String.t(),
          line: pos_integer()
        }

  @impl true
  def message(%__MODULE__{form: form, locale: locale, file: file, line: line}) do
    "plural form #{form} is required for locale #{inspect(locale)} " <>
      "but is missing for message compiled from #{file}:#{line}"
  end
end
