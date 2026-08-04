# WebSockAdapter

[![Build Status](https://github.com/phoenixframework/websock_adapter/workflows/Elixir%20CI/badge.svg)](https://github.com/phoenixframework/websock_adapter/actions)
[![Docs](https://img.shields.io/badge/api-docs-green.svg?style=flat)](https://hexdocs.pm/websock_adapter)
[![Hex.pm](https://img.shields.io/hexpm/v/websock_adapter.svg?style=flat&color=blue)](https://hex.pm/packages/websock_adapter)

WebSockAdapter is a library of adapters from common Web Servers to the
`WebSock` specification. WebSockAdapter currently supports
[Bandit](https://github.com/mtrudel/bandit) and
[Cowboy](https://github.com/ninenines/cowboy).

For details on the `WebSock` specification, consult the
[WebSock](https://hexdocs.pm/websock) documentation.

## Usage

WebSockAdapter makes it easy to upgrade Plug connections to WebSock connections.
Here's a simple example:

```elixir
defmodule EchoServer do
  def init(args) do
    {:ok, []}
  end

  def handle_in({"ping", [opcode: :text]}, state) do
    {:reply, :ok, {:text, "pong"}, state}
  end
end

defmodule MyPlug do
  use Plug.Router

  plug Plug.Logger
  plug :match
  plug :dispatch

  get "/" do
    # Provide the user with some useful instructions to copy & paste into their inspector
    send_resp(conn, 200, """
    Use the JavaScript console to interact using websockets

    sock  = new WebSocket("ws://localhost:4000/websocket")
    sock.addEventListener("message", console.log)
    sock.addEventListener("open", () => sock.send("ping"))
    """)
  end

  get "/websocket" do
    conn
    |> WebSockAdapter.upgrade(EchoServer, [], timeout: 60_000)
    |> halt()
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
```

This simple example illustrates many of the useful features of WebSock / WebSockAdapters:

* Implementing a WebSocket server is a single module, and looks & acts much like
  a GenServer does
* It's easy to pass state from the `WebSockAdapter.upgrade/3`
  call & have it show up in your WebSock callbacks
* Upgrades are handled as a plain Plug call. You are able to route requests to
  your upgrade endpoint using all of the power of the Plug API

If you're looking for more detail, Benjamin Milde has a [great blog
post](https://kobrakai.de/kolumne/bare-websockets) that goes a bit deeper than
the simple example above.

## Upgrade Validation

Since `0.5.5`, WebSockAdapter validates requests made via
`WebSockAdapter.upgrade/3` (this was and continues to also be done by the
underlying web server, but since the server's validation occurs after the
`Plug.call/2` lifecycle completes it's difficult to meaningfully handle such
errors). This validation examines the request for conformance to the clauses
laid out in RFC6455§4.2, as well as RFC8441§5 for HTTP/2 connections. Requests
which do not satisfy the requirements laid out in those specifications will
result in a `WebSockAdapter.UpgradeError` being raised, containing
details of the reason for the failure

## Installation

The websock_adapter package can be installed by adding `websock_adapter` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:websock_adapter, "~> 0.5"}
  ]
end
```

Documentation can be found at <https://hexdocs.pm/websock_adapter>.

## License

MIT
