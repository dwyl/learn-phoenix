defmodule Gettext.MissingBindingsError do
  @moduledoc """
  An error message raised for missing bindings errors.
  """

  @enforce_keys [:backend, :domain, :msgctxt, :locale, :msgid, :missing]
  defexception [:backend, :domain, :msgctxt, :locale, :msgid, :missing]

  @type t() :: %__MODULE__{}

  @impl true
  def message(%__MODULE__{
        backend: backend,
        domain: domain,
        msgctxt: msgctxt,
        locale: locale,
        msgid: msgid,
        missing: missing
      }) do
    "missing Gettext bindings: #{inspect(missing)} (backend #{inspect(backend)}, " <>
      "locale #{inspect(locale)}, domain #{inspect(domain)}, msgctxt #{inspect(msgctxt)}, " <>
      "msgid #{inspect(msgid)})"
  end
end
