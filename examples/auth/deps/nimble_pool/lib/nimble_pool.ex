defmodule NimblePool do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  use GenServer
  require Logger

  @type from :: {pid, reference}
  @type init_arg :: term
  @type pool_state :: term
  @type worker_state :: term
  @type client_state :: term
  @type user_reason :: term

  @typedoc since: "1.1.0"
  @type pool :: GenServer.server()

  @doc """
  Initializes the worker.

  It receives the worker argument passed to `start_link/1` if `c:init_pool/1` is
  not implemented, otherwise the pool state returned by `c:init_pool/1`. It must
  return `{:ok, worker_state, pool_state}` or `{:async, fun, pool_state}`, where the `fun`
  is a zero-arity function that must return the worker state.

  If this callback returns `{:async, fun, pool_state}`, `fun` is executed in a **separate
  one-off process**. Because of this, if you start resources that the pool needs to "own",
  you need to transfer ownership to the pool process. For example, if your async `fun`
  opens a `:gen_tcp` socket, you'll have to use `:gen_tcp.controlling_process/2` to transfer
  ownership back to the pool.

  > #### Blocking the pool {: .warning}
  >
  > This callback is synchronous and therefore will block the pool, potentially
  > for a significant amount of time since it's executed in the pool process once
  > per worker. > If you need to perform long initialization, consider using the
  > `{:async, fun, pool_state}` return type.
  """
  @doc callback: :worker
  @callback init_worker(pool_state) ::
              {:ok, worker_state, pool_state} | {:async, (-> worker_state), pool_state}

  @doc """
  Initializes the pool.

  It receives the worker argument passed to `start_link/1` and must
  return `{:ok, pool_state}` upon successful initialization,
  `:ignore` to exit normally, or `{:stop, reason}` to exit with `reason`
  and return `{:error, reason}`.

  This is a good place to perform a registration, for example.

  It must return the `pool_state`. The `pool_state` is given to
  `init_worker`. By default, it simply returns the given arguments.

  This callback is optional.

  ## Examples

      @impl NimblePool
      def init_pool(options) do
        Registry.register(options[:registry], :some_key, :some_value)
      end

  """
  @doc callback: :pool
  @callback init_pool(init_arg) :: {:ok, pool_state} | :ignore | {:stop, reason :: any()}

  @doc """
  Checks a worker out.

  The `maybe_wrapped_command` is the `command` passed to `checkout!/4` if the worker
  doesn't implement the `c:handle_enqueue/2` callback, otherwise it's the possibly-wrapped
  command returned by `c:handle_enqueue/2`.

  This callback must return one of:

    * `{:ok, client_state, worker_state, pool_state}` — the client state is given to
      the callback function passed to `checkout!/4`. `worker_state` and `pool_state`
      can potentially update the state of the checked-out worker and the pool.

    * `{:remove, reason, pool_state}` — `NimblePool` will remove the checked-out worker and
      attempt to checkout another worker.

    * `{:skip, Exception.t(), pool_state}` — `NimblePool` will skip the checkout, the client will
      raise the returned exception, and the worker will be left ready for the next
      checkout attempt.

  > #### Blocking the pool {: .warning}
  >
  > This callback is synchronous and therefore will block the pool.
  > Avoid performing long work in here. Instead, do as much work as
  > possible on the client.

  Once the worker is checked out, the worker won't handle any
  messages targeted to `c:handle_info/2`.
  """
  @doc callback: :worker
  @callback handle_checkout(maybe_wrapped_command :: term, from, worker_state, pool_state) ::
              {:ok, client_state, worker_state, pool_state}
              | {:remove, user_reason, pool_state}
              | {:skip, Exception.t(), pool_state}

  @doc """
  Checks a worker back in the pool.

  It receives the potentially-updated `client_state`, returned by the `checkout!/4`
  anonymous function, and it must return either
  `{:ok, worker_state, pool_state}` or `{:remove, reason, pool_state}`.

  > #### Blocking the pool {: .warning}
  >
  > This callback is synchronous and therefore will block the pool.
  > Avoid performing long work in here, instead do as much work as
  > possible on the client.

  Once the connection is checked in, it may immediately be handed
  to another client, without traversing any of the messages in the
  pool inbox.

  This callback is optional.
  """
  @doc callback: :worker
  @callback handle_checkin(client_state, from, worker_state, pool_state) ::
              {:ok, worker_state, pool_state} | {:remove, user_reason, pool_state}

  @doc """
  Handles an update instruction from a checked out worker.

  See `update/2` for more information.

  This callback is optional.
  """
  @doc callback: :worker
  @callback handle_update(message :: term, worker_state, pool_state) ::
              {:ok, worker_state, pool_state}

  @doc """
  Receives a message in the pool and handles it as each worker.

  It receives the `message` and it must return either
  `{:ok, worker_state}` to update the worker state, or `{:remove, reason}` to
  remove the worker.

  Since there is only a single pool process that can receive messages, this
  callback is executed once for every worker when the pool receives `message`.

  > #### Blocking the pool {: .warning}
  >
  > This callback is synchronous and therefore will block the pool while it
  > executes for each worker. Avoid performing long work in here.

  This callback is optional.
  """
  @doc callback: :worker
  @callback handle_info(message :: term, worker_state) ::
              {:ok, worker_state} | {:remove, user_reason}

  @doc """
  Executed by the pool whenever a request to check out a worker is enqueued.

  The `command` argument should be treated as an opaque value, but it can be
  wrapped with some data to be used in `c:handle_checkout/4`.

  It must return either `{:ok, maybe_wrapped_command, pool_state}` or
  `{:skip, Exception.t(), pool_state}` if checkout is to be skipped.

  > #### Blocking the pool {: .warning}
  >
  > This callback is synchronous and therefore will block the pool.
  > Avoid performing long work in here.

  This callback is optional.

  ## Examples

      @impl NimblePool
      def handle_enqueue(command, pool_state) do
        {:ok, {:wrapped, command}, pool_state}
      end

  """
  @doc callback: :pool
  @callback handle_enqueue(command :: term, pool_state) ::
              {:ok, maybe_wrapped_command :: term, pool_state}
              | {:skip, Exception.t(), pool_state}

  @doc """
  Terminates a worker.

  The `reason` argument is:

    * `:DOWN` whenever the client link breaks
    * `:timeout` whenever the client times out
    * one of `:throw`, `:error`, `:exit` whenever the client crashes with one
      of the reasons above.
    * `reason` if at any point you return `{:remove, reason}`
    * if any callback raises, the raised exception will be given as `reason`.

  It receives the latest known `worker_state`, which may not
  be the latest state. For example, if a client checks out the
  state and crashes, we don't fully know the `client_state`,
  so the `c:terminate_worker/3` callback needs to take such scenarios
  into account.

  This callback must always return `{:ok, pool_state}` with the potentially-updated
  pool state.

  This callback is optional.
  """
  @doc callback: :pool
  @callback terminate_worker(
              reason :: :DOWN | :timeout | :throw | :error | :exit | user_reason,
              worker_state,
              pool_state
            ) ::
              {:ok, pool_state}

  @doc """
  Handle pings due to inactivity on the worker.

  Executed whenever the idle worker periodic timer verifies that a worker has been idle
  on the pool for longer than the `:worker_idle_timeout` pool configuration (in milliseconds).

  This callback must return one of the following values:

    * `{:ok, worker_state}`: Updates worker state.

    * `{:remove, user_reason}`: The pool will proceed to the standard worker termination
        defined in `terminate_worker/3`.

    * `{:stop, user_reason}`: The entire pool process will be terminated, and `terminate_worker/3`
        will be called for every worker on the pool.

  This callback is optional.

  ## Max idle pings

  The `:max_idle_pings` pool option is useful to prevent sequential termination of a large number
  of workers. However, it is important to keep in mind the following behaviours whenever
  utilizing it.

    * If you are not terminating workers with `c:handle_ping/2`, you may end up pinging only
      the same workers over and over again because each cycle will ping only the first
      `:max_idle_pings` workers.

    * If you are terminating workers with `c:handle_ping/2`, the last worker may be terminated
      after up to `worker_idle_timeout + worker_idle_timeout * ceil(number_of_workers/max_idle_pings)`,
      instead of `2 * worker_idle_timeout` milliseconds of idle time.

  For instance consider a pool with 10 workers and a ping of 1 second.

  Given a negligible worker termination time and a worst-case scenario where all the workers
  go idle right after a verification cycle is started, then without `max_idle_pings` the
  last worker will be terminated in the next cycle (2 seconds), whereas with a
  `max_idle_pings` of 2 the last worker will be terminated only in the 5th cycle (6 seconds).

  ## Disclaimers

    * On lazy pools, if no worker is currently on the pool the callback will never be called.
      Therefore you can not rely on this callback to terminate empty lazy pools.

    * On not lazy pools, if you return `{:remove, user_reason}` you may end up
      terminating and initializing workers at the same time every idle verification cycle.

    * On large pools, if many resources go idle at the same cycle, you may end up terminating
      a large number of workers sequentially, which could lead to the pool being unable to
      fulfill requests. See `:max_idle_pings` option to prevent this.

  """
  @doc callback: :worker
  @callback handle_ping(
              worker_state,
              pool_state
            ) ::
              {:ok, worker_state} | {:remove, user_reason()} | {:stop, user_reason()}

  @doc """
  Handle pool termination.

  The `reason` argmument is the same given to GenServer's terminate/2 callback.

  It is not necessary to terminate workers here because the
  `terminate_worker/3` callback has already been invoked.

  This should be used only for clean up extra resources that can not be
  handled by `terminate_worker/3` callback.

  This callback is optional.
  """
  @doc callback: :pool
  @callback terminate_pool(
              reason :: :DOWN | :timeout | :throw | :error | :exit | user_reason,
              pool_state
            ) :: :ok

  @doc """
  Handle cancelled checkout requests.

  This callback is executed when a checkout request is cancelled unexpectedly.

  The context argument may be `:queued` or `:checked_out`:

  * `:queued` means the cancellation happened before resource checkout. This may happen
  when the pool is starving under load and can not serve resources.

  * `:checked_out` means the cancellation happened after resource checkout. This may happen
  when the function given to `checkout!/4` raises.

  This callback is optional.
  """
  @doc callback: :pool
  @callback handle_cancelled(
              context :: :queued | :checked_out,
              pool_state
            ) :: :ok

  @optional_callbacks init_pool: 1,
                      handle_checkin: 4,
                      handle_info: 2,
                      handle_enqueue: 2,
                      handle_update: 3,
                      handle_ping: 2,
                      terminate_worker: 3,
                      terminate_pool: 2,
                      handle_cancelled: 2

  @doc """
  Defines a pool to be started under the supervision tree.

  It accepts the same options as `start_link/1` with the
  addition or `:restart` and `:shutdown` that control the
  "Child Specification".

  ## Examples

      NimblePool.child_spec(worker: {__MODULE__, :some_arg}, restart: :temporary)

  """
  @spec child_spec(keyword) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    {worker, _} = Keyword.fetch!(opts, :worker)
    {restart, opts} = Keyword.pop(opts, :restart, :permanent)
    {shutdown, opts} = Keyword.pop(opts, :shutdown, 5_000)

    %{
      id: worker,
      start: {__MODULE__, :start_link, [opts]},
      shutdown: shutdown,
      restart: restart
    }
  end

  @doc """
  Starts a pool.

  ## Options

    * `:worker` - a `{worker_mod, worker_init_arg}` tuple with the worker
      module that implements the `NimblePool` behaviour and the worker
      initial argument. This argument is **required**.

    * `:pool_size` - how many workers in the pool. Defaults to `10`.

    * `:lazy` - When `true`, workers are started lazily, only when necessary.
      Defaults to `false`.

    * `:worker_idle_timeout` - Timeout in milliseconds to tag a worker as idle.
      If not nil, starts a periodic timer on the same frequency that will ping
      all idle workers using `handle_ping/2` optional callback .
      Defaults to no timeout.

    * `:max_idle_pings` - Defines a limit to the number of workers that can be pinged
      for each cycle of the `handle_ping/2` optional callback.
      Defaults to no limit. See `handle_ping/2` for more details.

  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {{worker, arg}, opts} =
      Keyword.pop_lazy(opts, :worker, fn ->
        raise ArgumentError, "missing required :worker option"
      end)

    {pool_size, opts} = Keyword.pop(opts, :pool_size, 10)
    {lazy, opts} = Keyword.pop(opts, :lazy, false)
    {worker_idle_timeout, opts} = Keyword.pop(opts, :worker_idle_timeout, nil)
    {max_idle_pings, opts} = Keyword.pop(opts, :max_idle_pings, -1)

    unless is_atom(worker) do
      raise ArgumentError, "worker must be an atom, got: #{inspect(worker)}"
    end

    unless is_integer(pool_size) and pool_size > 0 do
      raise ArgumentError, "pool_size must be a positive integer, got: #{inspect(pool_size)}"
    end

    GenServer.start_link(
      __MODULE__,
      {worker, arg, pool_size, lazy, worker_idle_timeout, max_idle_pings},
      opts
    )
  end

  @doc """
  Stops the given `pool`.

  The pool exits with the given `reason`. The pool has `timeout` milliseconds
  to terminate, otherwise it will be brutally terminated.

  ## Examples

      NimblePool.stop(pool)
      #=> :ok

  """
  @spec stop(pool, reason :: term, timeout) :: :ok
  def stop(pool, reason \\ :normal, timeout \\ :infinity) do
    GenServer.stop(pool, reason, timeout)
  end

  @doc """
  Checks out a worker from the pool.

  It expects a command, which will be passed to the `c:handle_checkout/4`
  callback. The `c:handle_checkout/4` callback will return a client state,
  which is given to the `function`.

  The `function` receives two arguments, the request
  (`{pid(), reference()}`) and the `client_state`.
  The function must return a two-element tuple, where the first element is the
  return value for `checkout!/4`, and the second element is the updated `client_state`,
  which will be given as the first argument to `c:handle_checkin/4`.

  `checkout!/4` also has an optional `timeout` value. This value will be applied
  to the checkout operation itself. The "check in" operation happens asynchronously.
  """
  @spec checkout!(pool, command :: term, function, timeout) :: result
        when function: (from, client_state -> {result, client_state}), result: var
  def checkout!(pool, command, function, timeout \\ 5_000) when is_function(function, 2) do
    # Re-implementation of gen.erl call to avoid multiple monitors.
    pid = GenServer.whereis(pool)

    unless pid do
      exit!(:noproc, :checkout, [pool])
    end

    ref = Process.monitor(pid)
    send_call(pid, ref, {:checkout, command, deadline(timeout)})

    receive do
      {^ref, {:skipped, exception}} ->
        raise exception

      {^ref, client_state} ->
        Process.demonitor(ref, [:flush])

        try do
          function.({pid, ref}, client_state)
        catch
          kind, reason ->
            send(pid, {__MODULE__, :cancel, ref, kind})
            :erlang.raise(kind, reason, __STACKTRACE__)
        else
          {result, client_state} ->
            send(pid, {__MODULE__, :checkin, ref, client_state})
            result
        end

      {:DOWN, ^ref, _, _, :noconnection} ->
        exit!({:nodedown, get_node(pid)}, :checkout, [pool])

      {:DOWN, ^ref, _, _, reason} ->
        exit!(reason, :checkout, [pool])
    after
      timeout ->
        send(pid, {__MODULE__, :cancel, ref, :timeout})
        Process.demonitor(ref, [:flush])
        exit!(:timeout, :checkout, [pool])
    end
  end

  @doc """
  Sends an **update** instruction to the pool about the checked out worker.

  This must be called inside the `checkout!/4` callback function with
  the `from` value given to `c:handle_checkout/4`.

  This is useful to update the pool's state before effectively
  checking the state in, which is handy when transferring
  resources requires two steps.
  """
  @spec update(from, command :: term) :: :ok
  def update({pid, ref} = _from, command) do
    send(pid, {__MODULE__, :update, ref, command})
    :ok
  end

  defp deadline(timeout) when is_integer(timeout) do
    System.monotonic_time() + System.convert_time_unit(timeout, :millisecond, :native)
  end

  defp deadline(:infinity), do: :infinity

  defp get_node({_, node}), do: node
  defp get_node(pid) when is_pid(pid), do: node(pid)

  defp send_call(pid, ref, message) do
    # Auto-connect is asynchronous. But we still use :noconnect to make sure
    # we send on the monitored connection, and not trigger a new auto-connect.
    Process.send(pid, {:"$gen_call", {self(), ref}, message}, [:noconnect])
  end

  defp exit!(reason, fun, args) do
    exit({reason, {__MODULE__, fun, args}})
  end

  ## Callbacks

  @impl true
  def init({worker, arg, pool_size, lazy, worker_idle_timeout, max_idle_pings}) do
    Process.flag(:trap_exit, true)

    case Code.ensure_loaded(worker) do
      {:module, _} ->
        :ok

      {:error, reason} ->
        raise ArgumentError, "failed to load worker module #{inspect(worker)}: #{inspect(reason)}"
    end

    lazy = if lazy, do: pool_size, else: nil

    if worker_idle_timeout do
      if function_exported?(worker, :handle_ping, 2) do
        Process.send_after(self(), :check_idle, worker_idle_timeout)
      else
        IO.warn(
          ":worker_idle_timeout was given but the worker does not export a handle_ping/2 callback"
        )
      end
    end

    with {:ok, pool_state} <- do_init_pool(worker, arg) do
      {pool_state, resources, async} =
        if is_nil(lazy) do
          Enum.reduce(1..pool_size, {pool_state, :queue.new(), %{}}, fn
            _, {pool_state, resources, async} ->
              init_worker(worker, pool_state, resources, async, worker_idle_timeout)
          end)
        else
          {pool_state, :queue.new(), %{}}
        end

      state = %{
        worker: worker,
        queue: :queue.new(),
        requests: %{},
        monitors: %{},
        resources: resources,
        async: async,
        state: pool_state,
        lazy: lazy,
        worker_idle_timeout: worker_idle_timeout,
        max_idle_pings: max_idle_pings
      }

      {:ok, state}
    end
  end

  @impl true
  def handle_call({:checkout, command, deadline}, {pid, ref} = from, state) do
    %{requests: requests, monitors: monitors, worker: worker, state: pool_state} = state
    mon_ref = Process.monitor(pid)
    requests = Map.put(requests, ref, {pid, mon_ref, :command, command, deadline})
    monitors = Map.put(monitors, mon_ref, ref)
    state = %{state | requests: requests, monitors: monitors}

    case handle_enqueue(worker, command, pool_state) do
      {:ok, command, pool_state} ->
        {:noreply, maybe_checkout(command, mon_ref, deadline, from, %{state | state: pool_state})}

      {:skip, exception, pool_state} ->
        state = remove_request(%{state | state: pool_state}, ref, mon_ref)
        {:reply, {:skipped, exception}, state}
    end
  end

  @impl true
  def handle_info({__MODULE__, :update, ref, command}, state) do
    %{requests: requests, state: pool_state, worker: worker} = state

    case requests do
      %{^ref => {pid, mon_ref, :state, worker_state}} ->
        {:ok, worker_state, pool_state} = worker.handle_update(command, worker_state, pool_state)
        requests = Map.put(requests, ref, {pid, mon_ref, :state, worker_state})
        {:noreply, %{state | requests: requests, state: pool_state}}

      %{} ->
        exit(:unexpected_precheckin)
    end
  end

  @impl true
  def handle_info({__MODULE__, :checkin, ref, worker_client_state}, state) do
    %{
      requests: requests,
      resources: resources,
      worker: worker,
      state: pool_state,
      worker_idle_timeout: worker_idle_timeout
    } = state

    case requests do
      %{^ref => {pid, mon_ref, :state, worker_server_state}} ->
        checkin =
          if function_exported?(worker, :handle_checkin, 4) do
            args = [worker_client_state, {pid, ref}, worker_server_state, pool_state]
            apply_worker_callback(pool_state, worker, :handle_checkin, args)
          else
            {:ok, worker_server_state, pool_state}
          end

        {resources, state} =
          case checkin do
            {:ok, worker_server_state, pool_state} ->
              {:queue.in({worker_server_state, get_metadata(worker_idle_timeout)}, resources),
               %{state | state: pool_state}}

            {:remove, reason, pool_state} ->
              {resources,
               remove_worker(reason, worker_server_state, %{state | state: pool_state})}
          end

        state = remove_request(state, ref, mon_ref)
        {:noreply, maybe_checkout(%{state | resources: resources})}

      %{} ->
        exit(:unexpected_checkin)
    end
  end

  @impl true
  def handle_info({__MODULE__, :cancel, ref, reason}, state) do
    cancel_request_ref(ref, reason, state)
  end

  @impl true
  def handle_info({__MODULE__, :init_worker}, state) do
    %{
      async: async,
      resources: resources,
      worker: worker,
      state: pool_state,
      worker_idle_timeout: worker_idle_timeout
    } = state

    {pool_state, resources, async} =
      init_worker(worker, pool_state, resources, async, worker_idle_timeout)

    {:noreply, maybe_checkout(%{state | async: async, resources: resources, state: pool_state})}
  end

  @impl true
  def handle_info({:DOWN, ref, _, _, _} = down, state) do
    %{monitors: monitors, async: async} = state

    case monitors do
      %{^ref => request_ref} ->
        cancel_request_ref(request_ref, :DOWN, state)

      %{} ->
        case async do
          %{^ref => _} -> remove_async_ref(ref, state)
          %{} -> maybe_handle_info(down, state)
        end
    end
  end

  @impl true
  def handle_info({:EXIT, pid, _reason} = exit, state) do
    %{async: async} = state

    case async do
      %{^pid => _} -> {:noreply, %{state | async: Map.delete(async, pid)}}
      %{} -> maybe_handle_info(exit, state)
    end
  end

  @impl true
  def handle_info({ref, worker_state} = reply, state) when is_reference(ref) do
    %{async: async, resources: resources, worker_idle_timeout: worker_idle_timeout} = state

    case async do
      %{^ref => _} ->
        Process.demonitor(ref, [:flush])
        resources = :queue.in({worker_state, get_metadata(worker_idle_timeout)}, resources)
        async = Map.delete(async, ref)
        state = %{state | async: async, resources: resources}
        {:noreply, maybe_checkout(state)}

      %{} ->
        maybe_handle_info(reply, state)
    end
  end

  @impl true
  def handle_info(
        :check_idle,
        %{resources: resources, worker_idle_timeout: worker_idle_timeout} = state
      ) do
    case check_idle_resources(resources, state) do
      {:ok, new_resources, new_state} ->
        Process.send_after(self(), :check_idle, worker_idle_timeout)
        {:noreply, %{new_state | resources: new_resources}}

      {:stop, reason, state} ->
        {:stop, {:shutdown, reason}, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    maybe_handle_info(msg, state)
  end

  @impl true
  def terminate(reason, %{worker: worker, resources: resources} = state) do
    for {worker_server_state, _} <- :queue.to_list(resources) do
      maybe_terminate_worker(reason, worker_server_state, state)
    end

    if function_exported?(worker, :terminate_pool, 2) do
      worker.terminate_pool(reason, state)
    end

    :ok
  end

  defp do_init_pool(worker, arg) do
    if function_exported?(worker, :init_pool, 1) do
      worker.init_pool(arg)
    else
      {:ok, arg}
    end
  end

  defp remove_async_ref(ref, state) do
    %{
      async: async,
      resources: resources,
      worker: worker,
      state: pool_state,
      worker_idle_timeout: worker_idle_timeout
    } = state

    # If an async worker failed to start, we try to start another one
    # immediately, even if the pool is lazy, as we assume there is an
    # immediate need for this resource.
    {pool_state, resources, async} =
      init_worker(worker, pool_state, resources, Map.delete(async, ref), worker_idle_timeout)

    {:noreply, %{state | resources: resources, async: async, state: pool_state}}
  end

  defp cancel_request_ref(
         ref,
         reason,
         %{requests: requests, worker: worker, state: pool_state} = state
       ) do
    case requests do
      # Exited or timed out before we could serve it
      %{^ref => {_, mon_ref, :command, _command, _deadline}} ->
        if function_exported?(worker, :handle_cancelled, 2) do
          args = [:queued, pool_state]
          apply_worker_callback(worker, :handle_cancelled, args)
        end

        {:noreply, remove_request(state, ref, mon_ref)}

      # Exited or errored during client processing
      %{^ref => {_, mon_ref, :state, worker_server_state}} ->
        if function_exported?(worker, :handle_cancelled, 2) do
          args = [:checked_out, pool_state]
          apply_worker_callback(worker, :handle_cancelled, args)
        end

        state = remove_request(state, ref, mon_ref)
        {:noreply, remove_worker(reason, worker_server_state, state)}

      # The client timed out, sent us a message, and we dropped the deadlined request
      %{} ->
        if function_exported?(worker, :handle_cancelled, 2) do
          args = [:queued, pool_state]
          apply_worker_callback(worker, :handle_cancelled, args)
        end

        {:noreply, state}
    end
  end

  defp maybe_handle_info(msg, state) do
    %{resources: resources, worker: worker, worker_idle_timeout: worker_idle_timeout} = state

    if function_exported?(worker, :handle_info, 2) do
      {resources, state} =
        Enum.reduce(:queue.to_list(resources), {:queue.new(), state}, fn
          {worker_server_state, _}, {resources, state} ->
            case apply_worker_callback(worker, :handle_info, [msg, worker_server_state]) do
              {:ok, worker_server_state} ->
                {:queue.in({worker_server_state, get_metadata(worker_idle_timeout)}, resources),
                 state}

              {:remove, reason} ->
                {resources, remove_worker(reason, worker_server_state, state)}
            end
        end)

      {:noreply, %{state | resources: resources}}
    else
      {:noreply, state}
    end
  end

  defp maybe_checkout(%{queue: queue, requests: requests} = state) do
    case :queue.out(queue) do
      {{:value, {pid, ref}}, queue} ->
        case requests do
          # The request still exists, so we are good to go
          %{^ref => {^pid, mon_ref, :command, command, deadline}} ->
            maybe_checkout(command, mon_ref, deadline, {pid, ref}, %{state | queue: queue})

          # It should never happen
          %{^ref => _} ->
            exit(:unexpected_checkout)

          # The request is no longer active, do nothing
          %{} ->
            maybe_checkout(%{state | queue: queue})
        end

      {:empty, _queue} ->
        state
    end
  end

  defp maybe_checkout(command, mon_ref, deadline, {pid, ref} = from, state) do
    if past_deadline?(deadline) do
      state = remove_request(state, ref, mon_ref)
      maybe_checkout(state)
    else
      %{resources: resources, requests: requests, worker: worker, queue: queue, state: pool_state} =
        state = init_worker_if_lazy_and_empty(state)

      case :queue.out(resources) do
        {{:value, {worker_server_state, _}}, resources} ->
          args = [command, from, worker_server_state, pool_state]

          case apply_worker_callback(pool_state, worker, :handle_checkout, args) do
            {:ok, worker_client_state, worker_server_state, pool_state} ->
              GenServer.reply({pid, ref}, worker_client_state)

              requests = Map.put(requests, ref, {pid, mon_ref, :state, worker_server_state})
              %{state | resources: resources, requests: requests, state: pool_state}

            {:remove, reason, pool_state} ->
              state = remove_worker(reason, worker_server_state, %{state | state: pool_state})
              maybe_checkout(command, mon_ref, deadline, from, %{state | resources: resources})

            {:skip, exception, pool_state} ->
              GenServer.reply({pid, ref}, {:skipped, exception})
              remove_request(%{state | state: pool_state}, ref, mon_ref)

            other ->
              raise """
              unexpected return from #{inspect(worker)}.handle_checkout/4.

              Expected: {:ok, client_state, server_state, pool_state} | {:remove, reason, pool_state} | {:skip, Exception.t(), pool_state}
              Got: #{inspect(other)}
              """
          end

        {:empty, _} ->
          %{state | queue: :queue.in(from, queue)}
      end
    end
  end

  defp init_worker_if_lazy_and_empty(%{lazy: nil} = state), do: state

  defp init_worker_if_lazy_and_empty(
         %{lazy: lazy, resources: resources, worker_idle_timeout: worker_idle_timeout} = state
       ) do
    if lazy > 0 and :queue.is_empty(resources) do
      %{async: async, worker: worker, state: pool_state} = state

      {pool_state, resources, async} =
        init_worker(worker, pool_state, resources, async, worker_idle_timeout)

      %{state | async: async, resources: resources, state: pool_state, lazy: lazy - 1}
    else
      state
    end
  end

  defp past_deadline?(deadline) when is_integer(deadline) do
    System.monotonic_time() >= deadline
  end

  defp past_deadline?(:infinity), do: false

  defp remove_worker(reason, worker_server_state, state) do
    state = maybe_terminate_worker(reason, worker_server_state, state)

    if lazy = state.lazy do
      %{state | lazy: lazy + 1}
    else
      schedule_init()
      state
    end
  end

  defp check_idle_resources(resources, state) do
    now_in_ms = System.monotonic_time(:millisecond)
    do_check_idle_resources(resources, now_in_ms, state, :queue.new(), state.max_idle_pings)
  end

  defp do_check_idle_resources(resources, _now_in_ms, state, new_resources, 0) do
    {:ok, :queue.join(new_resources, resources), state}
  end

  defp do_check_idle_resources(resources, now_in_ms, state, new_resources, remaining_pings) do
    case :queue.out(resources) do
      {:empty, _} ->
        {:ok, new_resources, state}

      {{:value, resource_data}, next_resources} ->
        {worker_server_state, worker_metadata} = resource_data
        time_diff = now_in_ms - worker_metadata

        if time_diff >= state.worker_idle_timeout do
          case maybe_ping_worker(worker_server_state, state) do
            {:ok, new_worker_state} ->
              # We don't need to update the worker_metadata because, by definition,
              # if we are checking for idle resources again and the timestamp is the same,
              # it is because it has to be checked again.
              new_resource_data = {new_worker_state, worker_metadata}
              new_resources = :queue.in(new_resource_data, new_resources)

              do_check_idle_resources(
                next_resources,
                now_in_ms,
                state,
                new_resources,
                remaining_pings - 1
              )

            {:remove, user_reason} ->
              new_state = remove_worker(user_reason, worker_server_state, state)

              do_check_idle_resources(
                next_resources,
                now_in_ms,
                new_state,
                new_resources,
                remaining_pings - 1
              )

            {:stop, reason} ->
              {:stop, reason, state}
          end
        else
          {:ok, :queue.join(new_resources, resources), state}
        end
    end
  end

  defp maybe_ping_worker(worker_server_state, state) do
    %{worker: worker, state: pool_state} = state

    args = [worker_server_state, pool_state]

    case apply_worker_callback(worker, :handle_ping, args) do
      {:ok, worker_state} ->
        {:ok, worker_state}

      {:remove, user_reason} ->
        {:remove, user_reason}

      {:stop, user_reason} ->
        {:stop, user_reason}

      other ->
        raise """
        unexpected return from #{inspect(worker)}.handle_ping/2.

        Expected:

          {:remove, reason}
          | {:ok, worker_state}
          | {:stop, reason}

        Got: #{inspect(other)}
        """
    end
  end

  defp maybe_terminate_worker(reason, worker_server_state, state) do
    %{worker: worker, state: pool_state} = state

    if function_exported?(worker, :terminate_worker, 3) do
      args = [reason, worker_server_state, pool_state]

      case apply_worker_callback(worker, :terminate_worker, args) do
        {:ok, pool_state} ->
          %{state | state: pool_state}

        {:remove, _reason} ->
          state

        other ->
          raise """
          unexpected return from #{inspect(worker)}.terminate_worker/3.

          Expected:

              {:ok, pool_state}

          Got: #{inspect(other)}
          """
      end
    else
      state
    end
  end

  defp init_worker(worker, pool_state, resources, async, worker_idle_timeout) do
    case apply_worker_callback(worker, :init_worker, [pool_state]) do
      {:ok, worker_state, pool_state} ->
        {pool_state, :queue.in({worker_state, get_metadata(worker_idle_timeout)}, resources),
         async}

      {:async, fun, pool_state} when is_function(fun, 0) ->
        %{ref: ref, pid: pid} = Task.Supervisor.async(NimblePool.TaskSupervisor, fun)
        {pool_state, resources, async |> Map.put(ref, pid) |> Map.put(pid, ref)}

      {:remove, _reason} ->
        send(self(), {__MODULE__, :init_worker})
        {pool_state, resources, async}

      other ->
        raise """
        unexpected return from #{inspect(worker)}.init_worker/1.

        Expected:

            {:ok, worker_state, pool_state}
            | {:async, (() -> worker_state), pool_state}

        Got: #{inspect(other)}
        """
    end
  end

  defp schedule_init() do
    send(self(), {__MODULE__, :init_worker})
  end

  defp apply_worker_callback(worker, fun, args) do
    do_apply_worker_callback(worker, fun, args, &{:remove, &1})
  end

  defp apply_worker_callback(pool_state, worker, fun, args) do
    do_apply_worker_callback(worker, fun, args, &{:remove, &1, pool_state})
  end

  defp do_apply_worker_callback(worker, fun, args, catch_fun) do
    try do
      apply(worker, fun, args)
    catch
      kind, reason ->
        reason = Exception.normalize(kind, reason, __STACKTRACE__)

        Logger.error(
          [
            "Error during #{inspect(worker)}.#{fun}/#{length(args)} callback:\n"
            | Exception.format(kind, reason, __STACKTRACE__)
          ],
          crash_reason: {crash_reason(kind, reason), __STACKTRACE__}
        )

        catch_fun.(reason)
    end
  end

  defp crash_reason(:throw, value), do: {:nocatch, value}
  defp crash_reason(_, value), do: value

  defp remove_request(pool_state, ref, mon_ref) do
    requests = Map.delete(pool_state.requests, ref)
    monitors = Map.delete(pool_state.monitors, mon_ref)
    Process.demonitor(mon_ref, [:flush])
    %{pool_state | requests: requests, monitors: monitors}
  end

  defp handle_enqueue(worker, command, pool_state) do
    if function_exported?(worker, :handle_enqueue, 2) do
      worker.handle_enqueue(command, pool_state)
    else
      {:ok, command, pool_state}
    end
  end

  defp get_metadata(nil), do: nil
  defp get_metadata(_worker_idle_timeout), do: System.monotonic_time(:millisecond)
end
