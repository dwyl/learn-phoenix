# NimblePool

[![hex.pm badge](https://img.shields.io/badge/Package%20on%20hex.pm-informational)](https://hex.pm/packages/nimble_pool)
[![Documentation badge](https://img.shields.io/badge/Documentation-ff69b4)][docs]
[![CI](https://github.com/dashbitco/nimble_pool/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/dashbitco/nimble_pool/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/dashbitco/nimble_pool/badge.svg?branch=main)](https://coveralls.io/github/dashbitco/nimble_pool?branch=main)

<!-- MDOC !-->

`NimblePool` is a tiny resource-pool implementation.

Pools in the Erlang VM, and therefore in Elixir, are generally process-based: they manage a group of processes. The downside of said pools is that when they have to manage resources, such as sockets or ports, the additional process leads to overhead.

In such pools, you usually end-up with two scenarios:

  * You invoke the pool manager, which returns the pooled process, which performs the operation on the socket or port for you, returning you the reply. This approach is non-optimal because all of the data sent and returned by the resource needs to be copied between processes

  * You invoke the pool manager, which returns the pooled process, which gives you access to the resource. Then you can act directly on the resource, avoiding the data copying, but you need to keep the state of the resource in sync with the process

NimblePool allows you to implement the second scenario without the addition of processes, which leads to a simpler and more efficient implementation. You should consider using NimblePool whenever you have to manage sockets, ports, or NIF resources and you want the client to perform one-off operations on them. For example, NimblePool is a good solution to manage HTTP/1 connections, ports that need to communicate with long-running programs, etc.

The downside of NimblePool is that, because all resources are under a single process, any resource management operation will happen on this single process, which is more likely to become a bottleneck. This can be addressed, however, by starting one NimblePool per scheduler and by doing scheduler-based dispatches.

NimblePool may not be a good option to manage processes. After all, the goal of NimblePool is to avoid creating processes for resources. If you already have a process, using a process-based pool such as `poolboy` will provide a better abstraction.

Finally, avoid using NimblePool to manage resources that support multiplexing, such as HTTP/2 connections. In fact, pools are not a good option to manage resources with multiplexing in general, as the pool removes the ability to multiplex.

## Types of callbacks

NimblePool has two types of callbacks. Worker callbacks and pool callbacks. The worker callbacks configure the behaviour of each worker, such as initialization, checkin and checkout. The pool callbacks configure general pool behaviour, such as initialization and queueing.

## Examples

To use `NimblePool`, you must define a module that implements the pool worker logic, outlined in the `NimblePool` behaviour.

### Port-based example

The example below keeps ports on the pool and check them out on every command. Please read the docs for `Port` before using the approach below, especially in regards to zombie ports.

```elixir
defmodule PortPool do
  @behaviour NimblePool

  @doc ~S"""
  Executes a given command against a port kept by the pool.

  First we start a pool of ports:

      iex> child = {NimblePool, worker: {PortPool, :cat}, name: PortPool}
      iex> Supervisor.start_link([child], strategy: :one_for_one)

  Now we can run commands against the ports in the pool:

      iex> PortPool.command(PortPool, "hello\n")
      "hello\n"
      iex> PortPool.command(PortPool, "world\n")
      "world\n"

  """
  def command(pool, command, opts \\ []) do
    pool_timeout = Keyword.get(opts, :pool_timeout, 5000)
    receive_timeout = Keyword.get(opts, :receive_timeout, 15000)

    NimblePool.checkout!(pool, :checkout, fn _from, port ->
      send(port, {self(), {:command, command}})

      receive do
        {^port, {:data, data}} ->
          try do
            Process.unlink(port)
            {data, :ok}
          rescue
            _ -> {data, :close}
          end
      after
        receive_timeout ->
          exit(:receive_timeout)
      end
    end, pool_timeout)
  end

  @impl NimblePool
  def init_worker(:cat = pool_state) do
    path = System.find_executable("cat")
    port = Port.open({:spawn_executable, path}, [:binary, args: ["-"]])
    {:ok, port, pool_state}
  end

  @impl NimblePool
  # Transfer the port to the caller
  def handle_checkout(:checkout, {pid, _}, port, pool_state) do
    Port.connect(port, pid)
    {:ok, port, port, pool_state}
  end

  @impl NimblePool
  # We got it back
  def handle_checkin(:ok, _from, port, pool_state) do
    {:ok, port, pool_state}
  end

  def handle_checkin(:close, _from, _port, pool_state) do
    {:remove, :closed, pool_state}
  end

  @impl NimblePool
  # On terminate, effectively close it
  def terminate_worker(_reason, port, pool_state) do
    Port.close(port)
    {:ok, pool_state}
  end
end
```

### HTTP/1-based example

The pool below uses [Mint](https://hexdocs.pm/mint) for HTTP/1 connections. It establishes connections eagerly. A better approach may be to establish connections lazily on checkout, as done by [Finch](https://github.com/keathley/finch), which is built on top of [Mint](https://github.com/elixir-mint/mint) + [NimbleOptions](https://github.com/dashbitco/nimble_options).

```elixir
defmodule HTTP1Pool do
  @behaviour NimblePool

  @doc ~S"""
  Executes a given command against a connection kept by the pool.

  First we start the pool:

      child = {NimblePool, worker: {HTTP1Pool, {:https, "elixir-lang.org", 443}}, name: HTTP1Pool}
      Supervisor.start_link([child], strategy: :one_for_one)

  Then we can use the connections in the pool:

      iex> HTTP1Pool.get(HTTP1Pool, "/")
      {:ok, %{status: 200, ...}}

  """
  def get(pool, path, opts \\ []) do
    pool_timeout = Keyword.get(opts, :pool_timeout, 5000)
    receive_timeout = Keyword.get(opts, :receive_timeout, 15000)

    NimblePool.checkout!(
      pool,
      :checkout,
      fn _from, conn ->
        {{kind, result_or_error}, conn} =
          with {:ok, conn, ref} <- Mint.HTTP1.request(conn, "GET", path, [], nil),
               {:ok, conn, result} <- receive_response([], conn, ref, %{}, receive_timeout) do
            {{:ok, result}, transfer_if_open(conn)}
          end

        {{kind, result_or_error}, conn}
      end,
      pool_timeout
    )
  end

  defp transfer_if_open(conn) do
    if Mint.HTTP1.open?(conn) do
      {:ok, conn}
    else
      :closed
    end
  end

  defp receive_response([], conn, ref, response, timeout) do
    {:ok, conn, entries} = Mint.HTTP1.recv(conn, 0, timeout)
    receive_response(entries, conn, ref, response, timeout)
  end

  defp receive_response([entry | entries], conn, ref, response, timeout) do
    case entry do
      {kind, ^ref, value} when kind in [:status, :headers] ->
        response = Map.put(response, kind, value)
        receive_response(entries, conn, ref, response, timeout)

      {:data, ^ref, data} ->
        response = Map.update(response, :data, data, &(&1 <> data))
        receive_response(entries, conn, ref, response, timeout)

      {:done, ^ref} ->
        {:ok, conn, response}

      {:error, ^ref, error} ->
        {:error, conn, error}
    end
  end

  @impl NimblePool
  def init_worker({scheme, host, port} = pool_state) do
    parent = self()

    async = fn ->
      # TODO: Add back-off
      {:ok, conn} = Mint.HTTP1.connect(scheme, host, port, [])
      {:ok, conn} = Mint.HTTP1.controlling_process(conn, parent)
      conn
    end

    {:async, async, pool_state}
  end

  @impl NimblePool
  # Transfer the conn to the caller.
  # If we lost the connection, then we remove it to try again.
  def handle_checkout(:checkout, _from, conn, pool_state) do
    with {:ok, conn} <- Mint.HTTP1.set_mode(conn, :passive) do
      {:ok, conn, conn, pool_state}
    else
      _ -> {:remove, :closed, pool_state}
    end
  end

  @impl NimblePool
  # We got it back.
  def handle_checkin(state, _from, _old_conn, pool_state) do
    with {:ok, conn} <- state,
         {:ok, conn} <- Mint.HTTP1.set_mode(conn, :active) do
      {:ok, conn, pool_state}
    else
      {:error, _} -> {:remove, :closed, pool_state}
    end
  end

  @impl NimblePool
  # If it is closed, drop it.
  def handle_info(message, conn) do
    case Mint.HTTP1.stream(conn, message) do
      {:ok, _, _} -> {:ok, conn}
      {:error, _, _, _} -> {:remove, :closed}
      :unknown -> {:ok, conn}
    end
  end

  @impl NimblePool
  # On terminate, effectively close it.
  # This will succeed even if it was already closed or if we don't own it.
  def terminate_worker(_reason, conn, pool_state) do
    Mint.HTTP1.close(conn)
    {:ok, pool_state}
  end
end
```

<!-- MDOC !-->

## Installation

Add `nimble_pool` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:nimble_pool, "~> 1.0"}]
end
```

## Nimble*

All nimble libraries by Dashbit:

  * [NimbleCSV](https://github.com/dashbitco/nimble_csv) - simple and fast CSV parsing
  * [NimbleOptions](https://github.com/dashbitco/nimble_options) - tiny library for validating and documenting high-level options
  * [NimbleParsec](https://github.com/dashbitco/nimble_parsec) - simple and fast parser combinators
  * [NimblePool](https://github.com/dashbitco/nimble_pool) - tiny resource-pool implementation
  * [NimblePublisher](https://github.com/dashbitco/nimble_publisher) - a minimal filesystem-based publishing engine with Markdown support and code highlighting
  * [NimbleTOTP](https://github.com/dashbitco/nimble_totp) - tiny library for generating time-based one time passwords (TOTP)

## License

Copyright 2019 Plataformatec \
Copyright 2020 Dashbit

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

[docs]: https://hexdocs.pm/nimble_pool
