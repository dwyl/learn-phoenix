defmodule DBConnection.Holder do
  @moduledoc false
  require Record

  @queue true
  @timeout 15000
  @time_unit 1000

  Record.defrecord(:conn, [:connection, :module, :state, :lock, :ts, deadline: nil, status: :ok])
  Record.defrecord(:pool_ref, [:pool, :reference, :deadline, :holder, :lock])

  @type t :: :ets.tid()
  @type checkin_time :: non_neg_integer() | nil

  ## Holder API

  @spec new(pid, reference, module, term) :: t
  def new(pool, ref, mod, state) do
    # Insert before setting heir so that pool can't receive empty table
    holder = :ets.new(__MODULE__, [:public, :ordered_set, decentralized_counters: true])

    conn = conn(connection: self(), module: mod, state: state, ts: System.monotonic_time())
    true = :ets.insert_new(holder, conn)

    :ets.setopts(holder, {:heir, pool, ref})
    holder
  end

  @spec update(pid, reference, module, term) :: {:ok, t} | :error
  def update(pool, ref, mod, state) do
    holder = new(pool, ref, mod, state)

    try do
      :ets.give_away(holder, pool, {:checkin, ref, System.monotonic_time()})
      {:ok, holder}
    rescue
      ArgumentError -> :error
    end
  end

  @spec delete(t) :: {module, term}
  def delete(holder) do
    [conn(module: module, state: state)] = :ets.lookup(holder, :conn)
    :ets.delete(holder)
    {module, state}
  end

  ## Pool API (invoked by caller)

  @callback checkout(pool :: GenServer.server(), [pid], opts :: Keyword.t()) ::
              {:ok, pool_ref :: any, module, checkin_time, state :: any}
              | {:error, Exception.t()}
  def checkout(pool, callers, opts) do
    queue? = Keyword.get(opts, :queue, @queue)
    now = System.monotonic_time(@time_unit)
    timeout = abs_timeout(now, opts)

    case checkout(pool, callers, queue?, now, timeout) do
      {:ok, _, _, _, _} = ok ->
        ok

      {:error, %DBConnection.ConnectionError{} = connection_error} = error ->
        :telemetry.execute(
          [:db_connection, :connection_error],
          %{count: 1},
          %{
            error: connection_error,
            opts: opts
          }
        )

        error

      {:error, _} = error ->
        error

      {:redirect, caller, proxy} ->
        case checkout(proxy, [caller], opts) do
          {:ok, _, _, _, _} = ok ->
            ok

          {:error, %DBConnection.ConnectionError{message: message} = exception} ->
            {:error,
             %{
               exception
               | message:
                   "could not checkout the connection owned by #{inspect(caller)}. " <>
                     "When using the sandbox, connections are shared, so this may imply " <>
                     "another process is using a connection. Reason: #{message}"
             }}

          {:error, _} = error ->
            error
        end

      {:exit, reason} ->
        exit({reason, {__MODULE__, :checkout, [pool, opts]}})
    end
  end

  @spec checkin(pool_ref :: any) :: :ok
  def checkin(pool_ref) do
    # Note we may call checkin after a disconnect/stop. For this reason, we choose
    # to not change the status on checkin but strictly speaking nobody can access
    # the holder after disconnect/stop unless they store a copy of %DBConnection{}.
    # Note status can't be :aborted as aborted is always reverted at the end of a
    # transaction.
    done(pool_ref, [{conn(:lock) + 1, nil}], :checkin, System.monotonic_time())
  end

  @spec disconnect(pool_ref :: any, err :: Exception.t()) :: :ok
  def disconnect(pool_ref, err) do
    done(pool_ref, [{conn(:status) + 1, :error}], :disconnect, err)
  end

  @spec stop(pool_ref :: any, err :: Exception.t()) :: :ok
  def stop(pool_ref, err) do
    done(pool_ref, [{conn(:status) + 1, :error}], :stop, err)
  end

  @spec handle(pool_ref :: any, fun :: atom, args :: [term], Keyword.t()) :: tuple
  def handle(pool_ref, fun, args, opts) do
    handle_or_cleanup(:handle, pool_ref, fun, args, opts)
  end

  @spec cleanup(pool_ref :: any, fun :: atom, args :: [term], Keyword.t()) :: tuple
  def cleanup(pool_ref, fun, args, opts) do
    handle_or_cleanup(:cleanup, pool_ref, fun, args, opts)
  end

  defp handle_or_cleanup(type, pool_ref, fun, args, opts) do
    pool_ref(holder: holder, lock: lock) = pool_ref

    try do
      :ets.lookup(holder, :conn)
    rescue
      ArgumentError ->
        msg = "connection is closed because of an error, disconnect or timeout"
        {:disconnect, DBConnection.ConnectionError.exception(msg), _state = :unused}
    else
      [conn(lock: conn_lock)] when conn_lock != lock ->
        raise "an outdated connection has been given to DBConnection on #{fun}/#{length(args) + 2}"

      [conn(status: :error)] ->
        msg = "connection is closed because of an error, disconnect or timeout"
        {:disconnect, DBConnection.ConnectionError.exception(msg), _state = :unused}

      [conn(status: :aborted)] when type != :cleanup ->
        msg = "transaction rolling back"
        {:disconnect, DBConnection.ConnectionError.exception(msg), _state = :unused}

      [conn(module: module, state: state)] ->
        holder_apply(holder, module, fun, args ++ [opts, state])
    end
  end

  ## Pool state helpers API (invoked by callers)

  @spec put_state(pool_ref :: any, term) :: :ok
  def put_state(pool_ref(holder: sink_holder), state) do
    :ets.update_element(sink_holder, :conn, [{conn(:state) + 1, state}])
    :ok
  end

  @spec status?(pool_ref :: any, :ok | :aborted) :: boolean()
  def status?(pool_ref(holder: holder), status) do
    try do
      :ets.lookup_element(holder, :conn, conn(:status) + 1) == status
    rescue
      ArgumentError -> false
    end
  end

  @spec put_status(pool_ref :: any, :ok | :aborted) :: boolean()
  def put_status(pool_ref(holder: holder), status) do
    try do
      :ets.update_element(holder, :conn, [{conn(:status) + 1, status}])
    rescue
      ArgumentError -> false
    end
  end

  ## Pool callbacks (invoked by pools)

  @spec reply_redirect({pid, reference}, pid | :shared | :auto, GenServer.server()) :: :ok
  def reply_redirect(from, caller, redirect) do
    GenServer.reply(from, {:redirect, caller, redirect})
    :ok
  end

  @spec reply_error({pid, reference}, Exception.t()) :: :ok
  def reply_error(from, exception) do
    GenServer.reply(from, {:error, exception})
    :ok
  end

  @spec handle_checkout(t, {pid, reference}, reference, checkin_time) :: boolean
  def handle_checkout(holder, {pid, mref}, ref, checkin_time) do
    :ets.give_away(holder, pid, {mref, ref, checkin_time})
  rescue
    ArgumentError ->
      if Process.alive?(pid) or :ets.info(holder, :owner) != self() do
        raise ArgumentError, no_holder(holder, pid)
      else
        false
      end
  end

  @spec handle_deadline(t, reference) :: boolean
  def handle_deadline(holder, deadline) do
    :ets.lookup_element(holder, :conn, conn(:deadline) + 1)
  rescue
    ArgumentError -> false
  else
    ^deadline -> true
    _ -> false
  end

  @spec handle_ping(t) :: true
  def handle_ping(holder) do
    :ets.lookup(holder, :conn)
  rescue
    ArgumentError ->
      raise ArgumentError, no_holder(holder, nil)
  else
    [conn(connection: conn, state: state)] ->
      DBConnection.Connection.ping({conn, holder}, state)
      :ets.delete(holder)
      true
  end

  @spec handle_disconnect(t, Exception.t()) :: boolean
  def handle_disconnect(holder, err) do
    handle_done(holder, &DBConnection.Connection.disconnect/3, err)
  end

  @spec handle_stop(t, term) :: boolean
  def handle_stop(holder, err) do
    handle_done(holder, &DBConnection.Connection.stop/3, err)
  end

  @spec maybe_disconnect(t, integer, non_neg_integer) :: boolean()
  def maybe_disconnect(holder, start, interval_ms) do
    ts = :ets.lookup_element(holder, :conn, conn(:ts) + 1)

    cond do
      ts >= start ->
        false

      interval_ms == 0 ->
        true

      true ->
        pid = :ets.lookup_element(holder, :conn, conn(:connection) + 1)
        System.monotonic_time() > hash_pid(pid, interval_ms) + start
    end
  rescue
    _ -> false
  else
    true ->
      opts = [message: "disconnect_all requested", severity: :debug]
      handle_disconnect(holder, DBConnection.ConnectionError.exception(opts))

    false ->
      false
  end

  ## Private

  defp checkout(pool, callers, queue?, start, timeout) do
    case GenServer.whereis(pool) do
      pid when node(pid) == node() ->
        checkout_call(pid, callers, queue?, start, timeout)

      pid when node(pid) != node() ->
        {:exit, {:badnode, node(pid)}}

      {_name, node} ->
        {:exit, {:badnode, node}}

      nil ->
        {:exit, :noproc}
    end
  end

  defp checkout_call(pid, callers, queue?, start, timeout) do
    lock = Process.monitor(pid)
    send(pid, {:db_connection, {self(), lock}, {:checkout, callers, start, queue?}})

    receive do
      {:"ETS-TRANSFER", holder, pool, {^lock, ref, checkin_time}} ->
        Process.demonitor(lock, [:flush])
        {deadline, ops} = start_deadline(timeout, pool, ref, holder, start)
        :ets.update_element(holder, :conn, [{conn(:lock) + 1, lock} | ops])

        pool_ref =
          pool_ref(pool: pool, reference: ref, deadline: deadline, holder: holder, lock: lock)

        checkout_result(holder, pool_ref, checkin_time)

      {^lock, reply} ->
        Process.demonitor(lock, [:flush])
        reply

      {:DOWN, ^lock, _, _, reason} ->
        {:exit, reason}
    end
  end

  defp checkout_result(holder, pool_ref, checkin_time) do
    try do
      :ets.lookup(holder, :conn)
    rescue
      ArgumentError ->
        # Deadline could hit and be handled pool before using connection
        msg = "connection not available because deadline reached while in queue"
        {:error, DBConnection.ConnectionError.exception(msg)}
    else
      [conn(module: mod, state: state)] ->
        {:ok, pool_ref, mod, checkin_time, state}
    end
  end

  defp no_holder(holder, maybe_pid) do
    reason =
      case :ets.info(holder, :owner) do
        :undefined -> "does not exist"
        ^maybe_pid -> "is being given to its current owner"
        owner when owner != self() -> "does not belong to the giving process"
        _ -> "could not be given away"
      end

    call_reason =
      if maybe_pid do
        "Error happened when attempting to transfer to #{inspect(maybe_pid)} " <>
          "(alive: #{Process.alive?(maybe_pid)})"
      else
        "Error happened when looking up connection"
      end

    """
    #{inspect(__MODULE__)} #{inspect(holder)} #{reason}, pool inconsistent.
    #{call_reason}.

    SELF: #{inspect(self())}
    ETS INFO: #{inspect(:ets.info(holder))}

    Please report at https://github.com/elixir-ecto/db_connection/issues"
    """
  end

  defp holder_apply(holder, module, fun, args) do
    try do
      apply(module, fun, args)
    catch
      kind, reason ->
        {:catch, kind, reason, __STACKTRACE__}
    else
      result when is_tuple(result) ->
        state = :erlang.element(:erlang.tuple_size(result), result)

        try do
          :ets.update_element(holder, :conn, {conn(:state) + 1, state})
          result
        rescue
          ArgumentError ->
            augment_disconnect(result)
        end

      # If it is not a tuple, we just return it as is so we raise bad return.
      result ->
        result
    end
  end

  defp augment_disconnect({:disconnect, %DBConnection.ConnectionError{} = err, state}) do
    %{message: message} = err

    message =
      message <>
        " (the connection was closed by the pool, " <>
        "possibly due to a timeout or because the pool has been terminated)"

    {:disconnect, %{err | message: message}, state}
  end

  defp augment_disconnect(result), do: result

  defp done(pool_ref, ops, tag, info) do
    pool_ref(pool: pool, reference: ref, deadline: deadline, holder: holder) = pool_ref
    cancel_deadline(deadline)

    try do
      :ets.update_element(holder, :conn, [{conn(:deadline) + 1, nil} | ops])
      :ets.give_away(holder, pool, {tag, ref, info})
    rescue
      ArgumentError -> :ok
    else
      true -> :ok
    end
  end

  defp handle_done(holder, stop, err) do
    :ets.lookup(holder, :conn)
  rescue
    ArgumentError ->
      false
  else
    [conn(connection: pid, deadline: deadline, state: state)] ->
      cancel_deadline(deadline)
      :ets.delete(holder)
      stop.({pid, holder}, err, state)
      true
  end

  defp abs_timeout(now, opts) do
    case Keyword.get(opts, :timeout, @timeout) do
      :infinity -> Keyword.get(opts, :deadline)
      timeout -> min(now + timeout, Keyword.get(opts, :deadline))
    end
  end

  defp start_deadline(nil, _, _, _, _) do
    {nil, []}
  end

  defp start_deadline(timeout, pid, ref, holder, start) do
    deadline =
      :erlang.start_timer(timeout, pid, {ref, holder, self(), timeout - start}, abs: true)

    {deadline, [{conn(:deadline) + 1, deadline}]}
  end

  defp cancel_deadline(nil) do
    :ok
  end

  defp cancel_deadline(deadline) do
    :erlang.cancel_timer(deadline, async: true, info: false)
  end

  defp hash_pid(pid, interval_ms) do
    hash = :erlang.phash2(pid, interval_ms)
    System.convert_time_unit(hash, :millisecond, :native)
  end
end
