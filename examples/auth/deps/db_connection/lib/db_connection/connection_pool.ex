defmodule DBConnection.ConnectionPool do
  @moduledoc """
  The default connection pool.

  The queueing algorithm is based on [CoDel](https://queue.acm.org/appendices/codel.html).

  You're not supposed to call any functions on this pool directly, but only pass this
  as the value of the `:pool` option in functions such as `DBConnection.start_link/2`.

  `disconnect_all/3`, which by default will result in connections being
  reestablished, can be called periodically to recycle checked-in connections
  after a maximum lifetime is reached. `Ecto SQL` users may find it at
  https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.html#disconnect_all/3
  """

  use GenServer
  alias DBConnection.Holder
  alias DBConnection.Util

  @behaviour DBConnection.Pool

  @queue_target 50
  @queue_interval 2000
  @idle_interval 1000
  @time_unit 1000

  @doc false
  def start_link({mod, opts}) do
    GenServer.start_link(__MODULE__, {mod, opts}, start_opts(opts))
  end

  @doc false
  @impl DBConnection.Pool
  def checkout(pool, callers, opts) do
    Holder.checkout(pool, callers, opts)
  end

  @doc false
  @impl DBConnection.Pool
  def disconnect_all(pool, interval, _opts) do
    GenServer.call(pool, {:disconnect_all, interval}, :infinity)
  end

  @doc false
  @impl DBConnection.Pool
  def get_connection_metrics(pool) do
    GenServer.call(pool, :get_connection_metrics, :infinity)
  end

  ## GenServer api

  @impl GenServer
  def init({mod, opts}) do
    DBConnection.register_as_pool(mod)

    queue = :ets.new(__MODULE__.Queue, [:protected, :ordered_set, decentralized_counters: true])
    ts = {System.monotonic_time(), 0}
    {:ok, _} = DBConnection.ConnectionPool.Pool.start_supervised(queue, mod, opts)
    target = Keyword.get(opts, :queue_target, @queue_target)
    interval = Keyword.get(opts, :queue_interval, @queue_interval)
    idle_interval = Keyword.get(opts, :idle_interval, @idle_interval)
    idle_limit = Keyword.get_lazy(opts, :idle_limit, fn -> Keyword.get(opts, :pool_size, 1) end)
    now_in_native = System.monotonic_time()
    now_in_ms = System.convert_time_unit(now_in_native, :native, @time_unit)

    codel = %{
      target: target,
      interval: interval,
      delay: 0,
      slow: false,
      next: now_in_ms,
      poll: nil,
      idle_interval: idle_interval,
      idle_limit: idle_limit,
      idle: nil
    }

    codel = start_idle(now_in_native, start_poll(now_in_ms, now_in_ms, codel))
    {:ok, {:busy, queue, codel, ts}}
  end

  @impl GenServer
  def handle_call(:get_connection_metrics, _from, {status, queue, _, _} = state) do
    {ready_conn_count, checkout_queue_length} =
      case status do
        :busy ->
          {0, :ets.select_count(queue, [{{{:_, :_, :_}}, [], [true]}])}

        :ready ->
          {:ets.select_count(queue, [{{{:_, :_}}, [], [true]}]), 0}
      end

    metrics = %{
      source: {:pool, self()},
      ready_conn_count: ready_conn_count,
      checkout_queue_length: checkout_queue_length
    }

    {:reply, [metrics], state}
  end

  def handle_call({:disconnect_all, interval}, _from, {type, queue, codel, _ts}) do
    ts = {System.monotonic_time(), interval}
    {:reply, :ok, {type, queue, codel, ts}}
  end

  @impl GenServer
  def handle_info(
        {:db_connection, from, {:checkout, _caller, now, queue?}},
        {:busy, queue, _, _} = busy
      ) do
    case queue? do
      true ->
        :ets.insert(queue, {{now, System.unique_integer(), from}})
        {:noreply, busy}

      false ->
        message = "connection not available and queuing is disabled"
        err = DBConnection.ConnectionError.exception(message)
        Holder.reply_error(from, err)
        {:noreply, busy}
    end
  end

  def handle_info(
        {:db_connection, from, {:checkout, _caller, _now, _queue?}} = checkout,
        {:ready, queue, _codel, _ts} = ready
      ) do
    case :ets.first(queue) do
      {queued_in_native, holder} = key ->
        Holder.handle_checkout(holder, from, queue, queued_in_native) and :ets.delete(queue, key)
        {:noreply, ready}

      :"$end_of_table" ->
        handle_info(checkout, put_elem(ready, 0, :busy))
    end
  end

  def handle_info({:"ETS-TRANSFER", holder, pid, queue}, {_, queue, _, _} = data) do
    message = "client #{Util.inspect_pid(pid)} exited"
    err = DBConnection.ConnectionError.exception(message: message, severity: :info)
    Holder.handle_disconnect(holder, err)
    {:noreply, data}
  end

  def handle_info({:"ETS-TRANSFER", holder, _, {msg, queue, extra}}, {_, queue, _, ts} = data) do
    case msg do
      :checkin ->
        owner = self()

        case :ets.info(holder, :owner) do
          ^owner ->
            {time, interval} = ts

            if Holder.maybe_disconnect(holder, time, interval) do
              {:noreply, data}
            else
              handle_checkin(holder, extra, data)
            end

          :undefined ->
            {:noreply, data}
        end

      :disconnect ->
        Holder.handle_disconnect(holder, extra)
        {:noreply, data}

      :stop ->
        Holder.handle_stop(holder, extra)
        {:noreply, data}
    end
  end

  def handle_info({:timeout, deadline, {queue, holder, pid, len}}, {_, queue, _, _} = data) do
    # Check that timeout refers to current holder (and not previous)
    if Holder.handle_deadline(holder, deadline) do
      message =
        "client #{Util.inspect_pid(pid)} timed out because " <>
          "it queued and checked out the connection for longer than #{len}ms"

      exc =
        case Process.info(pid, :current_stacktrace) do
          {:current_stacktrace, stacktrace} ->
            message <>
              "\n\n#{Util.inspect_pid(pid)} was at location:\n\n" <>
              Exception.format_stacktrace(stacktrace)

          _ ->
            message
        end
        |> DBConnection.ConnectionError.exception()

      Holder.handle_disconnect(holder, exc)
    end

    {:noreply, data}
  end

  def handle_info({:timeout, poll, {time, last_sent}}, {_, _, %{poll: poll}, _} = data) do
    {status, queue, codel, ts} = data

    # If no queue progress since last poll check queue
    case :ets.first(queue) do
      {sent, _, _} when sent <= last_sent and status == :busy ->
        delay = time - sent
        timeout(delay, time, queue, start_poll(time, sent, codel), ts)

      {sent, _, _} ->
        {:noreply, {status, queue, start_poll(time, sent, codel), ts}}

      _ ->
        {:noreply, {status, queue, start_poll(time, time, codel), ts}}
    end
  end

  def handle_info({:timeout, idle, past_in_native}, {_, _, %{idle: idle}, _} = data) do
    {status, queue, %{idle_limit: limit} = codel, ts} = data
    drop_idle(past_in_native, limit, status, queue, codel, ts)
  end

  defp drop_idle(past_in_native, limit, status, queue, codel, ts) do
    with true <- status == :ready and limit > 0,
         {queued_in_native, holder} = key when queued_in_native <= past_in_native <-
           :ets.first(queue) do
      :ets.delete(queue, key)
      Holder.maybe_disconnect(holder, elem(ts, 0), 0) or Holder.handle_ping(holder)
      drop_idle(past_in_native, limit - 1, status, queue, codel, ts)
    else
      _ ->
        {:noreply, {status, queue, start_idle(System.monotonic_time(), codel), ts}}
    end
  end

  defp timeout(delay, time, queue, codel, ts) do
    case codel do
      %{delay: min_delay, next: next, target: target, interval: interval}
      when time >= next and min_delay > target ->
        codel = %{codel | slow: true, delay: delay, next: time + interval}
        drop_slow(time, target * 2, queue)
        {:noreply, {:busy, queue, codel, ts}}

      %{next: next, interval: interval} when time >= next ->
        codel = %{codel | slow: false, delay: delay, next: time + interval}
        {:noreply, {:busy, queue, codel, ts}}

      _ ->
        {:noreply, {:busy, queue, codel, ts}}
    end
  end

  defp drop_slow(time, timeout, queue) do
    min_sent = time - timeout
    match = {{:"$1", :_, :"$2"}}
    guards = [{:<, :"$1", min_sent}]
    select_slow = [{match, guards, [{{:"$1", :"$2"}}]}]

    for {sent, from} <- :ets.select(queue, select_slow) do
      drop(time - sent, from)
    end

    :ets.select_delete(queue, [{match, guards, [true]}])
  end

  defp handle_checkin(holder, now_in_native, {:ready, queue, _, _} = data) do
    :ets.insert(queue, {{now_in_native, holder}})
    {:noreply, data}
  end

  defp handle_checkin(holder, now_in_native, {:busy, queue, codel, ts}) do
    now_in_ms = System.convert_time_unit(now_in_native, :native, @time_unit)

    case dequeue(now_in_ms, holder, queue, codel, ts) do
      {:busy, _, _, _} = busy ->
        {:noreply, busy}

      {:ready, _, _, _} = ready ->
        :ets.insert(queue, {{now_in_native, holder}})
        {:noreply, ready}
    end
  end

  defp dequeue(time, holder, queue, codel, ts) do
    case codel do
      %{next: next, delay: delay, target: target} when time >= next ->
        dequeue_first(time, delay > target, holder, queue, codel, ts)

      %{slow: false} ->
        dequeue_fast(time, holder, queue, codel, ts)

      %{slow: true, target: target} ->
        dequeue_slow(time, target * 2, holder, queue, codel, ts)
    end
  end

  defp dequeue_first(time, slow?, holder, queue, codel, ts) do
    %{interval: interval} = codel
    next = time + interval

    case :ets.first(queue) do
      {sent, _, from} = key ->
        :ets.delete(queue, key)
        delay = time - sent
        codel = %{codel | next: next, delay: delay, slow: slow?}
        go(delay, from, time, holder, queue, codel, ts)

      :"$end_of_table" ->
        codel = %{codel | next: next, delay: 0, slow: slow?}
        {:ready, queue, codel, ts}
    end
  end

  defp dequeue_fast(time, holder, queue, codel, ts) do
    case :ets.first(queue) do
      {sent, _, from} = key ->
        :ets.delete(queue, key)
        go(time - sent, from, time, holder, queue, codel, ts)

      :"$end_of_table" ->
        {:ready, queue, %{codel | delay: 0}, ts}
    end
  end

  defp dequeue_slow(time, timeout, holder, queue, codel, ts) do
    case :ets.first(queue) do
      {sent, _, from} = key when time - sent > timeout ->
        :ets.delete(queue, key)
        drop(time - sent, from)
        dequeue_slow(time, timeout, holder, queue, codel, ts)

      {sent, _, from} = key ->
        :ets.delete(queue, key)
        go(time - sent, from, time, holder, queue, codel, ts)

      :"$end_of_table" ->
        {:ready, queue, %{codel | delay: 0}, ts}
    end
  end

  defp go(delay, from, time, holder, queue, %{delay: min} = codel, ts) do
    case Holder.handle_checkout(holder, from, queue, 0) do
      true when delay < min ->
        {:busy, queue, %{codel | delay: delay}, ts}

      true ->
        {:busy, queue, codel, ts}

      false ->
        dequeue(time, holder, queue, codel, ts)
    end
  end

  defp drop(delay, from) do
    message = """
    connection not available and request was dropped from queue after #{delay}ms. \
    This means requests are coming in and your connection pool cannot serve them fast enough. \
    You can address this by:

      1. Ensuring your database is available and that you can connect to it
      2. Tracking down slow queries and making sure they are running fast enough
      3. Increasing the pool_size (although this increases resource consumption)
      4. Allowing requests to wait longer by increasing :queue_target and :queue_interval

    See DBConnection.start_link/2 for more information
    """

    err = DBConnection.ConnectionError.exception(message, :queue_timeout)

    Holder.reply_error(from, err)
  end

  defp start_opts(opts) do
    Keyword.take(opts, [:name, :spawn_opt])
  end

  defp start_poll(now, last_sent, %{interval: interval} = codel) do
    timeout = now + interval
    poll = :erlang.start_timer(timeout, self(), {timeout, last_sent}, abs: true)
    %{codel | poll: poll}
  end

  defp start_idle(now_in_native, %{idle_interval: interval} = codel) do
    timeout = System.convert_time_unit(now_in_native, :native, :millisecond) + interval
    idle = :erlang.start_timer(timeout, self(), now_in_native, abs: true)
    %{codel | idle: idle}
  end
end
