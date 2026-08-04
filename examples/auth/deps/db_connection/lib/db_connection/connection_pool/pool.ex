defmodule DBConnection.ConnectionPool.Pool do
  @moduledoc false
  use Supervisor, restart: :temporary

  def start_supervised(tag, mod, opts) do
    DBConnection.Watcher.watch(
      DBConnection.ConnectionPool.Supervisor,
      {DBConnection.ConnectionPool.Pool, {self(), tag, mod, opts}}
    )
  end

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg)
  end

  @impl true
  def init({owner, tag, mod, opts}) do
    size = Keyword.get(opts, :pool_size, 1)

    if size < 1, do: raise(ArgumentError, "pool size must be greater or equal to 1, got #{size}")

    children = for id <- 1..size, do: conn(owner, tag, id, mod, opts)
    sup_opts = [strategy: :one_for_one] ++ Keyword.take(opts, [:max_restarts, :max_seconds])
    Supervisor.init(children, sup_opts)
  end

  ## Helpers

  defp conn(owner, tag, id, mod, opts) do
    child_opts = [id: {mod, owner, id}] ++ Keyword.take(opts, [:shutdown])
    DBConnection.Connection.child_spec(mod, [pool_index: id] ++ opts, owner, tag, child_opts)
  end
end
