defmodule DBConnection.Watcher do
  @moduledoc false
  @name __MODULE__

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  def watch(supervisor, args) do
    GenServer.call(@name, {:watch, supervisor, args}, :infinity)
  end

  @impl true
  def init(:ok) do
    Process.flag(:trap_exit, true)
    {:ok, {%{}, %{}}}
  end

  @impl true
  def handle_call({:watch, supervisor, args}, {caller_pid, _ref}, {caller_refs, started_refs}) do
    case DynamicSupervisor.start_child(supervisor, args) do
      {:ok, started_pid} ->
        Process.link(caller_pid)
        caller_ref = Process.monitor(caller_pid)
        started_ref = Process.monitor(started_pid)
        caller_refs = Map.put(caller_refs, caller_ref, {supervisor, started_pid, started_ref})
        started_refs = Map.put(started_refs, started_ref, {caller_pid, caller_ref})
        {:reply, {:ok, started_pid}, {caller_refs, started_refs}}

      other ->
        {:reply, other, {caller_refs, started_refs}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, _, _, _}, {caller_refs, started_refs}) do
    case caller_refs do
      %{^ref => {supervisor, started_pid, started_ref}} ->
        Process.demonitor(started_ref, [:flush])
        DynamicSupervisor.terminate_child(supervisor, started_pid)
        {:noreply, {Map.delete(caller_refs, ref), Map.delete(started_refs, started_ref)}}

      %{} ->
        %{^ref => {caller_pid, caller_ref}} = started_refs
        Process.demonitor(caller_ref, [:flush])
        Process.exit(caller_pid, :kill)
        {:noreply, {Map.delete(caller_refs, caller_ref), Map.delete(started_refs, ref)}}
    end
  end

  def handle_info({:EXIT, _, _}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_, {_, started_refs}) do
    for {_, {caller_pid, _}} <- started_refs do
      Process.exit(caller_pid, :kill)
    end

    :ok
  end
end
