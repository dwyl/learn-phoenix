defmodule DBConnection.TelemetryListener do
  @moduledoc """
  A connection listener that emits telemetry events for connection and disconnection

  It monitors connection processes and ensures that disconnection events are
  always emitted.

  ## Usage

  Start the listener, and pass it under the `:connection_listeners` option when
  starting DBConnection:

      {:ok, pid} = DBConnection.TelemetryListener.start_link()
      {:ok, _conn} = DBConnection.start_link(SomeModule, connection_listeners: [pid])

      # Using a tag, which will be sent in telemetry metadata
      {:ok, _conn} = DBConnection.start_link(SomeModule, connection_listeners: {[pid], :my_tag})

      # Or, with a Supervisor:
      Supervisor.start_link([
        {DBConnection.TelemetryListener, name: MyListener},
        DBConnection.child_spec(SomeModule, connection_listeners: {[MyListener], :my_tag})
      ])

  When using with Ecto, you can pass the `connection_listeners` option to Ecto, and we
  recommend passing the repository as the tag. In your supervision tree:

      Supervisor.start_link([
        {DBConnection.TelemetryListener, name: MyApp.DBListener},
        {MyApp.Repo, connection_listeners: {[MyApp.DBListener], MyApp.Repo})
      ])

  ## Telemetry events

  ### Connected

  `[:db_connection, :connected]` - Executed after a connection is established.

  #### Measurements

    * `:count` - Always 1

  #### Metadata

    * `:pid` - The connection pid
    * `:tag` - The connection pool tag

  ### Disconnected

  `[:db_connection, :disconnected]` - Executed after a disconnect.

  #### Measurements

    * `:count` - Always 1

  #### Metadata

    * `:pid` - The connection pid
    * `:tag` - The connection pool tag
  """

  use GenServer

  @doc "Starts a telemetry listener"
  @spec start_link(GenServer.options()) :: {:ok, pid()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  @impl GenServer
  def init(nil) do
    {:ok, %{monitoring: %{}}}
  end

  @impl GenServer
  def handle_info({:connected, pid, tag}, state) do
    handle_connected(pid, tag, state)
  end

  def handle_info({:connected, pid}, state) do
    handle_connected(pid, nil, state)
  end

  def handle_info({:disconnected, pid, _}, state) do
    handle_disconnected(pid, state)
  end

  def handle_info({:disconnected, pid}, state) do
    handle_disconnected(pid, state)
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    handle_disconnected(pid, state)
  end

  defp handle_connected(pid, tag, state) do
    :telemetry.execute([:db_connection, :connected], %{count: 1}, %{tag: tag, pid: pid})
    ref = Process.monitor(pid)

    {:noreply, put_in(state.monitoring[pid], {ref, tag})}
  end

  defp handle_disconnected(pid, state) do
    case state.monitoring[pid] do
      # Already handled. We may receive two messages: one from monitor and one
      # from listener. For this reason, we need to handle both.
      nil ->
        {:noreply, state}

      {ref, tag} ->
        Process.demonitor(ref, [:flush])
        :telemetry.execute([:db_connection, :disconnected], %{count: 1}, %{tag: tag, pid: pid})
        {:noreply, %{state | monitoring: Map.delete(state.monitoring, pid)}}
    end
  end
end
