defmodule DBConnection.ConnectionError do
  @moduledoc """
  A generic connection error exception.

  The raised exception might include the reason which would be useful
  to programmatically determine what was causing the error.
  """

  @typedoc since: "2.7.0"
  @type t() :: %__MODULE__{
          message: String.t(),
          reason: :error | :queue_timeout,
          severity: Logger.level()
        }

  defexception [:message, severity: :error, reason: :error]

  @doc false
  def exception(message, reason) when is_binary(message) and reason in [:error, :queue_timeout] do
    message
    |> exception()
    |> Map.replace!(:reason, reason)
  end
end
