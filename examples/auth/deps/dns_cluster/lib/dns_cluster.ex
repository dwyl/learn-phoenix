defmodule DNSCluster do
  @moduledoc """
  Simple DNS based cluster discovery.

  A DNS query is made every `:interval` milliseconds to discover new ips.

  ## Default node discovery
  Nodes will only be joined if their node basename matches the basename of the current node.
  For example, if `node()` is `myapp-123@fdaa:1:36c9:a7b:198:c4b1:73c6:1`, it will try to connect
  to every IP from the DNS query with `Node.connect/1`. But this will only work if the remote node
  has the same basename, like `myapp-123@fdaa:1:36c9:a7b:198:c4b1:73c6:2`. If the remote node's
  basename is different, the nodes will not connect.

  ## Specifying remote basenames
  If you want to connect to nodes with different basenames, use a tuple with the basename and query.
  For example, to connect to a node named `remote`, use `{"remote", "remote-app.internal"}`.

  ## Multiple queries
  Sometimes you might want to cluster apps with different domain names. Just pass a list of queries
  for this. For instance: `["app-one.internal", "app-two.internal", {"other-basename", "other.internal"}]`.
  Remember, all nodes need to share the same secret cookie to connect successfully.

  ## Examples

  To start in your supervision tree, add the child:

      children = [
        ...,
        {DNSCluster, query: "myapp.internal"}
      ]

  See the `start_link/1` docs for all available options.

  If you require more advanced clustering options and strategies, see the
  [libcluster](https://hexdocs.pm/libcluster) library.
  """
  use GenServer
  require Logger

  defmodule Resolver do
    @moduledoc false

    require Record
    Record.defrecord(:hostent, Record.extract(:hostent, from_lib: "kernel/include/inet.hrl"))

    def basename(node_name) when is_atom(node_name) do
      [basename, _] = String.split(to_string(node_name), "@")
      basename
    end

    def connect_node(node_name) when is_atom(node_name), do: Node.connect(node_name)

    def list_nodes, do: Node.list(:visible)

    def lookup(query, type) when is_binary(query) and type in [:a, :aaaa] do
      case :inet_res.getbyname(~c"#{query}", type) do
        {:ok, hostent(h_addr_list: addr_list)} -> addr_list
        {:error, _} -> []
      end
    end
  end

  @doc ~S"""
  Starts DNS based cluster discovery.

  ## Options

    * `:name` - the name of the cluster. Defaults to `DNSCluster`.
    * `:query` - the required DNS query for node discovery, for example:
      `"myapp.internal"` or `["foo.internal", "bar.internal"]`. If the basename
      differs between nodes, a tuple of `{basename, query}` can be provided as well.
      The value `:ignore` can be used to ignore starting the DNSCluster.
    * `:interval` - the millisec interval between DNS queries. Defaults to `5000`.
    * `:connect_timeout` - the millisec timeout to allow discovered nodes to connect.
      Defaults to `10_000`.

  ## Examples

      iex> DNSCluster.start_link(query: "myapp.internal")
      {:ok, pid}

      iex> DNSCluster.start_link(query: :ignore)
      :ignore
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    case Keyword.fetch(opts, :query) do
      {:ok, :ignore} ->
        :ignore

      {:ok, query} ->
        if valid_query?(query) do
          warn_on_invalid_dist()
          resolver = Keyword.get(opts, :resolver, Resolver)

          state = %{
            interval: Keyword.get(opts, :interval, 5_000),
            basename: resolver.basename(node()),
            query: List.wrap(query),
            log: Keyword.get(opts, :log, false),
            poll_timer: nil,
            connect_timeout: Keyword.get(opts, :connect_timeout, 10_000),
            resolver: resolver
          }

          {:ok, state, {:continue, :discover_ips}}
        else
          raise ArgumentError,
                "expected :query to be a string, {basename, query}, or list, got: #{inspect(query)}"
        end

      :error ->
        raise ArgumentError, "missing required :query option in #{inspect(opts)}"
    end
  end

  @impl true
  def handle_continue(:discover_ips, state) do
    {:noreply, do_discovery(state)}
  end

  @impl true
  def handle_info(:discover_ips, state) do
    {:noreply, do_discovery(state)}
  end

  defp do_discovery(state) do
    state
    |> connect_new_nodes()
    |> schedule_next_poll()
  end

  defp connect_new_nodes(%{resolver: resolver, connect_timeout: timeout} = state) do
    node_names = for name <- resolver.list_nodes(), into: MapSet.new(), do: to_string(name)

    ips = discover_ips(state)

    _results =
      ips
      |> Enum.map(fn {basename, ip} -> "#{basename}@#{ip}" end)
      |> Enum.filter(fn node_name -> !Enum.member?(node_names, node_name) end)
      |> Task.async_stream(
        fn new_name ->
          if resolver.connect_node(:"#{new_name}") do
            log(state, "#{node()} connected to #{new_name}")
          end
        end,
        max_concurrency: max(1, length(ips)),
        timeout: timeout
      )
      |> Enum.to_list()

    state
  end

  defp log(state, msg) do
    if level = state.log, do: Logger.log(level, msg)
  end

  defp schedule_next_poll(state) do
    %{state | poll_timer: Process.send_after(self(), :discover_ips, state.interval)}
  end

  defp discover_ips(%{resolver: resolver, query: queries} = state) do
    [:a, :aaaa]
    |> Enum.flat_map(fn type ->
      Enum.flat_map(queries, fn query ->
        {basename, query} =
          case query do
            {basename, query} ->
              # use the user-specified basename
              {basename, query}

            query when is_binary(query) ->
              # no basename specified, use host basename
              {state.basename, query}
          end

        for addr <- resolver.lookup(query, type) do
          {basename, addr}
        end
      end)
    end)
    |> Enum.uniq()
    |> Enum.map(fn {basename, addr} -> {basename, to_string(:inet.ntoa(addr))} end)
  end

  defp valid_query?(list) do
    list
    |> List.wrap()
    |> Enum.all?(fn
      string when is_binary(string) -> true
      {basename, query} when is_binary(basename) and is_binary(query) -> true
      _ -> false
    end)
  end

  defp warn_on_invalid_dist do
    release? = is_binary(System.get_env("RELEASE_NAME"))
    net_state = if function_exported?(:net_kernel, :get_state, 0), do: :net_kernel.get_state()

    cond do
      !net_state ->
        :ok

      net_state.started == :no and release? ->
        Logger.warning("""
        node not running in distributed mode. Ensure the following exports are set in your rel/env.sh.eex file:

            #!/bin/sh

            export RELEASE_DISTRIBUTION=name
            export RELEASE_NODE="myapp@fully-qualified-host-or-ip"
        """)

      net_state.started == :no or
          (!release? and net_state.started != :no and net_state[:name_domain] != :longnames) ->
        Logger.warning("""
        node not running in distributed mode. When running outside of a release, you must start net_kernel manually with
        longnames.
        https://www.erlang.org/doc/man/net_kernel.html#start-2
        """)

      net_state[:name_domain] != :longnames and release? ->
        Logger.warning("""
        node not running with longnames which are required for DNS discovery.
        Ensure the following exports are set in your rel/env.sh.eex file:

            #!/bin/sh

            export RELEASE_DISTRIBUTION=name
            export RELEASE_NODE="myapp@fully-qualified-host-or-ip"
        """)

      true ->
        :ok
    end
  end
end
