defmodule DBConnection.Ownership.Proxy do
  @moduledoc false

  alias DBConnection.Holder
  alias DBConnection.Util
  use GenServer, restart: :temporary

  @time_unit 1000
  @ownership_timeout 120_000
  @queue_target 50
  @queue_interval 1000

  def start_link({caller, pool, pool_opts}) do
    GenServer.start_link(__MODULE__, {caller, pool, pool_opts}, [])
  end

  def stop(proxy, caller) do
    GenServer.cast(proxy, {:stop, caller})
  end

  # Callbacks

  @impl true
  def init({caller, pool, pool_opts}) do
    Util.set_label("db_ownership_proxy")

    pool_opts =
      pool_opts
      |> Keyword.put(:timeout, :infinity)
      |> Keyword.delete(:deadline)

    owner_ref = Process.monitor(caller)
    ownership_timeout = Keyword.get(pool_opts, :ownership_timeout, @ownership_timeout)
    timeout = Keyword.get(pool_opts, :queue_target, @queue_target) * 2
    interval = Keyword.get(pool_opts, :queue_interval, @queue_interval)

    pre_checkin = Keyword.get(pool_opts, :pre_checkin, fn _, mod, state -> {:ok, mod, state} end)
    post_checkout = Keyword.get(pool_opts, :post_checkout, &{:ok, &1, &2})

    state = %{
      client: nil,
      timer: nil,
      holder: nil,
      timeout: timeout,
      interval: interval,
      poll: nil,
      owner: {caller, owner_ref},
      pool: pool,
      pool_ref: nil,
      pool_opts: pool_opts,
      queue: :queue.new(),
      mod: nil,
      pre_checkin: pre_checkin,
      post_checkout: post_checkout,
      ownership_timer: start_timer(caller, ownership_timeout)
    }

    now = System.monotonic_time(@time_unit)
    {:ok, start_poll(now, state)}
  end

  @impl true
  def handle_info({:DOWN, ref, _, pid, _reason}, %{owner: {_, ref}} = state) do
    down("owner #{Util.inspect_pid(pid)} exited", state)
  end

  def handle_info({:timeout, deadline, {_ref, holder, pid, len}}, %{holder: holder} = state) do
    if Holder.handle_deadline(holder, deadline) do
      message =
        "client #{Util.inspect_pid(pid)} timed out because " <>
          "it queued and checked out the connection for longer than #{len}ms"

      down(message, state)
    else
      {:noreply, state}
    end
  end

  def handle_info(
        {:timeout, timer, {__MODULE__, pid, timeout}},
        %{ownership_timer: timer} = state
      ) do
    message =
      "owner #{Util.inspect_pid(pid)} timed out because " <>
        "it owned the connection for longer than #{timeout}ms (set via the :ownership_timeout option)"

    # We don't invoke down because this is always a disconnect, even if there is no client.
    # On the other hand, those timeouts are unlikely to trigger, as it defaults to 2 mins.
    pool_disconnect(DBConnection.ConnectionError.exception(message), state)
  end

  def handle_info({:timeout, poll, time}, %{poll: poll} = state) do
    state = timeout(time, state)
    {:noreply, start_poll(time, state)}
  end

  def handle_info(
        {:db_connection, from, {:checkout, _caller, _now, _queue?}},
        %{holder: nil} = state
      ) do
    %{pool: pool, pool_opts: pool_opts, owner: {_, owner_ref}, post_checkout: post_checkout} =
      state

    case Holder.checkout(pool, [self()], pool_opts) do
      {:ok, pool_ref, original_mod, _idle_time, conn_state} ->
        case post_checkout.(original_mod, conn_state) do
          {:ok, conn_mod, conn_state} ->
            holder = Holder.new(self(), owner_ref, conn_mod, conn_state)
            state = %{state | pool_ref: pool_ref, holder: holder, mod: original_mod}
            checkout(from, state)

          {:disconnect, err, ^original_mod, _conn_state} ->
            Holder.disconnect(pool_ref, err)
            Holder.reply_error(from, err)
            {:stop, {:shutdown, err}, state}
        end

      {:error, err} ->
        Holder.reply_error(from, err)
        {:stop, {:shutdown, err}, state}
    end
  end

  def handle_info(
        {:db_connection, from, {:checkout, _caller, _now, _queue?}},
        %{client: nil} = state
      ) do
    checkout(from, state)
  end

  def handle_info({:db_connection, from, {:checkout, _caller, now, queue?}}, state) do
    if queue? do
      %{queue: queue} = state
      queue = :queue.in({now, from}, queue)
      {:noreply, %{state | queue: queue}}
    else
      message = "connection not available and queuing is disabled"
      err = DBConnection.ConnectionError.exception(message)
      Holder.reply_error(from, err)
      {:noreply, state}
    end
  end

  def handle_info(
        {:"ETS-TRANSFER", holder, _, {msg, ref, extra}},
        %{holder: holder, client: {_, ref, _}} = state
      ) do
    case msg do
      :checkin -> checkin(state)
      :disconnect -> pool_disconnect(extra, state)
      :stop -> pool_stop(extra, state)
    end
  end

  def handle_info({:"ETS-TRANSFER", holder, pid, ref}, %{holder: holder, owner: {_, ref}} = state) do
    down("client #{Util.inspect_pid(pid)} exited", state)
  end

  @impl true
  def handle_cast({:stop, caller}, %{owner: {owner, _}} = state) do
    message = "#{inspect(caller)} checked in the connection owned by #{inspect(owner)}"

    message =
      case pruned_stacktrace(caller) do
        [] ->
          message

        current_stack ->
          message <>
            "\n\n#{inspect(caller)} triggered the checkin at location:\n\n" <>
            Exception.format_stacktrace(current_stack)
      end

    down(message, state)
  end

  @impl true
  def handle_call(
        :get_connection_metrics,
        _,
        %{queue: queue, holder: holder, client: client} = state
      ) do
    connection_metrics = %{
      source: {:proxy, self()},
      ready_conn_count:
        if is_nil(holder) or not is_nil(client) do
          0
        else
          1
        end,
      checkout_queue_length: :queue.len(queue)
    }

    {:reply, connection_metrics, state}
  end

  defp checkout({pid, ref} = from, %{holder: holder} = state) do
    if Holder.handle_checkout(holder, from, ref, nil) do
      {:noreply, %{state | client: {pid, ref, pruned_stacktrace(pid)}}}
    else
      next(state)
    end
  end

  defp checkin(state) do
    next(%{state | client: nil})
  end

  defp next(%{queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, {_, from}}, queue} ->
        checkout(from, %{state | queue: queue})

      {:empty, queue} ->
        {:noreply, %{state | queue: queue}}
    end
  end

  defp start_timer(_, :infinity), do: nil

  defp start_timer(pid, timeout) do
    :erlang.start_timer(timeout, self(), {__MODULE__, pid, timeout})
  end

  # It is down but never checked out from pool
  defp down(reason, %{holder: nil} = state) do
    {:stop, {:shutdown, reason}, state}
  end

  # If it is down but it has no client, checkin
  defp down(reason, %{client: nil} = state) do
    pool_checkin(reason, state)
  end

  # If it is down but it has a client, disconnect
  defp down(reason, %{client: {client, _, checkout_stack}} = state) do
    reason =
      case pruned_stacktrace(client) do
        [] ->
          reason

        current_stack ->
          reason <>
            """
            \n\nClient #{inspect(client)} is still using a connection from owner at location:

            #{Exception.format_stacktrace(current_stack)}
            The connection itself was checked out by #{inspect(client)} at location:

            #{Exception.format_stacktrace(checkout_stack)}
            """
      end

    err = DBConnection.ConnectionError.exception(reason)
    pool_disconnect(err, state)
  end

  ## Helpers

  defp pool_checkin(reason, state) do
    pool_done(reason, state, :checkin, fn pool_ref, _ -> Holder.checkin(pool_ref) end)
  end

  defp pool_disconnect(err, state) do
    pool_done(err, state, {:disconnect, err}, &Holder.disconnect/2)
  end

  defp pool_stop(err, state) do
    pool_done(err, state, {:stop, err}, &Holder.stop/2, &Holder.stop/2)
  end

  defp pool_done(err, state, op, done, stop_or_disconnect \\ &Holder.disconnect/2) do
    %{holder: holder, pool_ref: pool_ref, pre_checkin: pre_checkin, mod: original_mod} = state

    if holder do
      {conn_mod, conn_state} = Holder.delete(holder)

      case pre_checkin.(op, conn_mod, conn_state) do
        {:ok, ^original_mod, conn_state} ->
          Holder.put_state(pool_ref, conn_state)
          done.(pool_ref, err)
          {:stop, {:shutdown, err}, state}

        {:disconnect, err, ^original_mod, conn_state} ->
          Holder.put_state(pool_ref, conn_state)
          stop_or_disconnect.(pool_ref, err)
          {:stop, {:shutdown, err}, state}
      end
    else
      {:stop, {:shutdown, err}, state}
    end
  end

  defp start_poll(now, %{interval: interval} = state) do
    timeout = now + interval
    poll = :erlang.start_timer(timeout, self(), timeout, abs: true)
    %{state | poll: poll}
  end

  defp timeout(time, %{queue: queue, timeout: timeout} = state) do
    case :queue.out(queue) do
      {{:value, {sent, from}}, queue} when sent + timeout < time ->
        drop(time - sent, from)
        timeout(time, %{state | queue: queue})

      {_, _} ->
        state
    end
  end

  defp drop(delay, from) do
    message =
      "connection not available and request was dropped from queue after #{delay}ms. " <>
        "You can configure how long requests wait in the queue using :queue_target and " <>
        ":queue_interval. See DBConnection.start_link/2 for more information"

    err = DBConnection.ConnectionError.exception(message, :queue_timeout)
    Holder.reply_error(from, err)
  end

  @prune_modules [:gen, GenServer, DBConnection, DBConnection.Holder, DBConnection.Ownership]

  defp pruned_stacktrace(pid) do
    case Process.info(pid, :current_stacktrace) do
      {:current_stacktrace, stacktrace} ->
        Enum.drop_while(stacktrace, &match?({mod, _, _, _} when mod in @prune_modules, &1))

      _ ->
        []
    end
  end
end
