defmodule Rumbl.UserSocket do
  use Phoenix.Socket

  # Channels
  channel "videos:*", Rumbl.VideoChannel

  ## Transports
  transport :websocket, Phoenix.Transports.WebSocket
  # transport :longpoll, Phoenix.Transports.LongPoll

  @max_age 2 * 7 * 24 * 60 * 60 # two weeks

  def connect(%{"token" => token}, socket) do
    case Phoenix.Token.verify(socket, "user socket", token, max_age: @max_age) do
      {:ok, user_id} ->
        {:ok, assign(socket, :user_id, user_id)}
      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, socket), do: :error

  def id(socket), do: "users_socket:#{socket.assigns.user_id}"

end
