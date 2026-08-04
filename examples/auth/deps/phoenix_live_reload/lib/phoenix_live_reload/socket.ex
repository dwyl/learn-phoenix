defmodule Phoenix.LiveReloader.Socket do
  @moduledoc """
  The Socket handler for live reload channels.
  """
  use Phoenix.Socket, log: false

  channel "phoenix:live_reload", Phoenix.LiveReloader.Channel

  def connect(_params, socket), do: {:ok, socket}

  def id(_socket), do: nil
end
