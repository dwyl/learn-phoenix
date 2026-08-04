# WebSock

[![Build Status](https://github.com/phoenixframework/websock/workflows/Elixir%20CI/badge.svg)](https://github.com/phoenixframework/websock/actions)
[![Docs](https://img.shields.io/badge/api-docs-green.svg?style=flat)](https://hexdocs.pm/websock)
[![Hex.pm](https://img.shields.io/hexpm/v/websock.svg?style=flat&color=blue)](https://hex.pm/packages/websock)

WebSock is a specification for apps to service WebSocket connections; you can
think of it as 'Plug for WebSockets'. WebSock abstracts WebSocket support from
servers such as [Bandit][] or [Cowboy][] and exposes a generic WebSocket API to
applications. WebSocket-aware applications such as Phoenix can then be hosted
within a supported web server simply by defining conformance to the `WebSock`
behaviour, in the same manner as how Plug conformance allows their HTTP aspects
to be hosted within an arbitrary web server.

<!-- MDOC -->
Defines the `WebSock` behaviour which describes the functions that
an application such as Phoenix must implement in order to be WebSock compliant;
it is roughly the equivalent of the `Plug` interface, but for WebSocket
connections. It is commonly used in conjunction with the [websock_adapter][]
package which defines concrete adapters on top of [Bandit][] and [Cowboy][];
the two packages are separate to allow for servers which directly expose
`WebSock` support to depend on just the behaviour. Users will almost always
want to depend on [websock_adapter][] instead of this package.

## WebSocket Lifecycle

WebSocket connections go through a well defined lifecycle mediated by `WebSock`
and `WebSock.Adapters`:

* **This step is outside the scope of the WebSock API**. A client will
  attempt to Upgrade an HTTP connection to a WebSocket connection by passing
  a specific set of headers in an HTTP request. An application may choose to
  determine the feasibility of such an upgrade request however it pleases
* An application will then signal an upgrade to be performed by calling
  `WebSockAdapter.upgrade/4`, passing in the `Plug.Conn` to upgrade, along with
  the `WebSock` compliant handler module which will handle the connection once
  it is upgraded
* The underlying server will then attempt to upgrade the HTTP connection to a WebSocket connection
* Assuming the WebSocket connection is successfully negotiated, WebSock will
  call `c:WebSock.init/1` on the configured handler to allow the application to perform any necessary
  tasks now that the WebSocket connection is live
* WebSock will call the configured handler's `c:WebSock.handle_in/2` callback
  whenever data is received from the client
* WebSock will call the configured handler's `c:WebSock.handle_info/2` callback
  whenever other processes send messages to the handler process
* The `WebSock` implementation can send data to the client by returning
  a `{:push,...}` tuple from any of the above `handle_*` callbacks
* At any time, `c:WebSock.terminate/2` (if implemented) may be called to indicate a close, error or
  timeout condition

[Cowboy]: https://github.com/ninenines/cowboy
[Bandit]: https://github.com/mtrudel/bandit/
[websock_adapter]: https://hex.pm/packages/websock_adapter
<!-- MDOC -->

For more information, consult the [docs](https://hexdocs.pm/websock).

## Installation

The websock package can be installed by adding `websock` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:websock, "~> 0.5"}
  ]
end
```

Documentation can be found at <https://hexdocs.pm/websock>.

## License

MIT
