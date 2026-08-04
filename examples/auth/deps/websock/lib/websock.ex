defmodule WebSock do
  @external_resource Path.join([__DIR__, "../README.md"])

  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  @typedoc "The type of an implementing module"
  @type impl :: module()

  @typedoc "The type of state passed into / returned from `WebSock` callbacks"
  @type state :: term()

  @typedoc "Possible data frame types"
  @type data_opcode :: :text | :binary

  @typedoc "Possible control frame types"
  @type control_opcode :: :ping | :pong

  @typedoc "All possible frame types"
  @type opcode :: data_opcode() | control_opcode()

  @typedoc "The structure of an outbound message"
  @type message :: {opcode(), iodata() | nil}

  @typedoc "Convenience type for one or many outbound messages"
  @type messages :: message() | [message()]

  @typedoc "The result as returned from init, handle_in, handle_control & handle_info calls"
  @type handle_result ::
          {:push, messages(), state()}
          | {:reply, term(), messages(), state()}
          | {:ok, state()}
          | {:stop, {:shutdown, :restart} | term(), state()}
          | {:stop, term(), close_detail(), state()}
          | {:stop, term(), close_detail(), messages(), state()}

  @typedoc "Details about why a connection was closed"
  @type close_reason :: :normal | :remote | :shutdown | :timeout | {:error, term()}

  @typedoc "Describes the data to send in a connection close frame"
  @type close_detail :: integer() | {integer(), iodata() | nil}

  @doc """
  Called by WebSock after a WebSocket connection has been established (that is, after the server
  has accepted the connection & the WebSocket handshake has been successfully completed).
  Implementations can use this callback to perform tasks such as subscribing the client to any
  relevant subscriptions within the application, or any other task which should be undertaken at
  the time the connection is established

  The return value from this callback is handled as described in `c:handle_in/2`
  """
  @callback init(term()) :: handle_result()

  @doc """
  Called by WebSock when a frame is received from the client. WebSock will only call this function
  once a complete frame has been received (that is, once any continuation frames have been
  received).

  The return value from this callback are processed as follows:

  * `{:push, messages(), state()}`: The indicated message(s) are sent to the client. The
    indicated state value is used to update the socket's current state
  * `{:reply, term(), messages(), state()}`: The indicated message(s) are sent to the client. The
    indicated state value is used to update the socket's current state. The second element of the
    tuple has no semantic meaning in this context and is ignored. This return tuple is included
    here solely for backwards compatibility with the `Phoenix.Socket.Transport` behaviour; it is in
    all respects semantically identical to the `{:push, ...}` return value previously described
  * `{:ok, state()}`: The indicated state value is used to update the socket's current state
  * `{:stop, reason :: term(), state()}`: The connection will be closed based on the indicated
    reason. If `reason` is `:normal`, `c:terminate/2` will be called with a `reason` value of
    `:normal`. If the `reason` is `{:shutdown, :restart}`, the server is restarting and
    the WebSocket adapter should close with the `1012` Service Restart code.
    In all other cases, it will be called with `{:error, reason}`. Server
    implementations should also use this value when determining how to close the connection with
    the client
  * `{:stop, reason :: term(), close_detail(), state()}`: Similar to the previous clause, but allows
    for the explicit setting of either a plain close code or a close code with a body to be sent to
    the client
  * `{:stop, reason :: term(), close_detail(), messages(), state()}`: Similar to the previous clause, but allows
    for the sending of one or more frames before sending the connection close frame to the client
  """
  @callback handle_in({binary(), opcode: data_opcode()}, state()) :: handle_result()

  @doc """
  Called by WebSock when a ping or pong frame has been received from the client. Note that
  implementations SHOULD NOT send a pong frame in response; this MUST be automatically done by the
  web server before this callback has been called.

  Despite the name of this callback, it is not called for connection close frames even though they
  are technically control frames. WebSock will handle any received connection
  close frames and issue calls to `c:terminate/2` as / if appropriate

  This callback is optional

  The return value from this callback is handled as described in `c:handle_in/2`
  """
  @callback handle_control({binary(), opcode: control_opcode()}, state()) :: handle_result()

  @doc """
  Called by WebSock when the socket process receives a `c:GenServer.handle_info/2` call which was
  not otherwise processed by the server implementation.

  The return value from this callback is handled as described in `c:handle_in/2`
  """
  @callback handle_info(term(), state()) :: handle_result()

  @doc """
  Called by WebSock when a connection is closed. `reason` may be one of the following:

  * `:normal`: The local end shut down the connection normally, by returning a `{:stop, :normal,
    state()}` tuple from one of the `WebSock.handle_*` callbacks
  * `:remote`: The remote end shut down the connection
  * `:shutdown`: The local server is being shut down
  * `:timeout`: No data has been sent or received for more than the configured timeout duration
  * `{:error, reason}`: An error occurred. This may be the result of error
    handling in the local server, or the result of a `WebSock.handle_*` callback returning a `{:stop,
    reason, state}` tuple where reason is any value other than `:normal`

  This callback is optional

  The return value of this callback is ignored
  """
  @callback terminate(reason :: close_reason(), state()) :: any()

  @optional_callbacks handle_control: 2, terminate: 2
end
