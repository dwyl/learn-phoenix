defmodule DBConnection.Task do
  @moduledoc false
  @name __MODULE__

  require DBConnection.Holder

  def run_child(mod, state, fun, opts) do
    arg = [fun, self(), opts]
    {:ok, pid} = Task.Supervisor.start_child(@name, __MODULE__, :init, arg)
    ref = Process.monitor(pid)
    _ = DBConnection.Holder.update(pid, ref, mod, state)
    {pid, ref}
  end

  def init(fun, parent, opts) do
    DBConnection.Util.set_label("db_after_connect_task")

    try do
      Process.link(parent)
    catch
      :error, :noproc ->
        exit({:shutdown, :noproc})
    end

    receive do
      {:"ETS-TRANSFER", holder, ^parent, {:checkin, ref, _extra}} ->
        Process.unlink(parent)
        pool_ref = DBConnection.Holder.pool_ref(pool: parent, reference: ref, holder: holder)
        checkout = {:via, __MODULE__, pool_ref}
        _ = DBConnection.run(checkout, make_fun(fun), [pool: __MODULE__] ++ opts)
        exit(:normal)
    end
  end

  def checkout({:via, __MODULE__, pool_ref}, _callers, _opts) do
    {:ok, pool_ref, _mod = :unused, _idle_time = nil, _state = :unused}
  end

  defp make_fun(fun) when is_function(fun, 1) do
    fun
  end

  defp make_fun(mfargs) do
    fn conn ->
      {mod, fun, args} = mfargs
      apply(mod, fun, [conn | args])
    end
  end
end
