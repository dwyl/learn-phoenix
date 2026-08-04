defmodule Ecto.Adapters.SQL.Sandbox do
  @moduledoc ~S"""
  A pool for concurrent transactional tests.

  The sandbox pool is implemented on top of an ownership mechanism.
  When started, the pool is in automatic mode, which means the
  repository will automatically check connections out as with any
  other pool.

  The `mode/2` function can be used to change the pool mode from
  automatic to either manual or shared. In the latter two modes,
  the connection must be explicitly checked out before use.
  When explicit checkouts are made, the sandbox will wrap the
  connection in a transaction by default and control who has
  access to it. This means developers have a safe mechanism for
  running concurrent tests against the database.

  ## Database support

  While both PostgreSQL and MySQL support SQL Sandbox, only PostgreSQL
  supports concurrent tests while running the SQL Sandbox. Therefore, do
  not run concurrent tests with MySQL as you may run into deadlocks due to
  its transaction implementation.

  ## Example

  The first step is to configure your database to use the
  `Ecto.Adapters.SQL.Sandbox` pool. You set those options in your
  `config/config.exs` (or preferably `config/test.exs`) if you
  haven't yet:

      config :my_app, Repo,
        pool: Ecto.Adapters.SQL.Sandbox

  Now with the test database properly configured, you can write
  transactional tests:

      # At the end of your test_helper.exs
      # Set the pool mode to manual for explicit checkouts
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)

      defmodule PostTest do
        # Once the mode is manual, tests can also be async
        use ExUnit.Case, async: true

        setup do
          # Explicitly get a connection before each test
          :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
        end

        test "create post" do
          # Use the repository as usual
          assert %Post{} = Repo.insert!(%Post{})
        end
      end

  ## Collaborating processes

  The example above is straight-forward because we have only
  a single process using the database connection. However,
  sometimes a test may need to interact with multiple processes,
  all using the same connection so they all belong to the same
  transaction.

  Before we discuss solutions, let's see what happens if we try
  to use a connection from a new process without explicitly
  checking it out first:

      setup do
        # Explicitly get a connection before each test
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
      end

      test "calls worker that runs a query" do
        GenServer.call(MyApp.Worker, :run_query)
      end

  The test above will fail with an error similar to:

      ** (DBConnection.OwnershipError) cannot find ownership process for #PID<0.35.0>

  That's because the `setup` block is checking out the connection only
  for the test process. Once the worker attempts to perform a query,
  there is no connection assigned to it and it will fail.

  The sandbox module provides two ways of doing so, via allowances or
  by running in shared mode.

  ### Allowances

  The idea behind allowances is that you can explicitly tell a process
  which checked out connection it should use, allowing multiple processes
  to collaborate over the same connection. Let's give it a try:

      test "calls worker that runs a query" do
        allow = Process.whereis(MyApp.Worker)
        Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), allow)
        GenServer.call(MyApp.Worker, :run_query)
      end

  And that's it, by calling `allow/3`, we are explicitly assigning
  the parent's connection (i.e. the test process' connection) to
  the task.

  Because allowances use an explicit mechanism, their advantage
  is that you can still run your tests in async mode. The downside
  is that you need to explicitly control and allow every single
  process. This is not always possible. In such cases, you will
  want to use shared mode.

  ### Shared mode

  Shared mode allows a process to share its connection with any other
  process automatically, without relying on explicit allowances.
  Let's change the example above to use shared mode:

      setup do
        # Explicitly get a connection before each test
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
        # Setting the shared mode must be done only after checkout
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      end

      test "calls worker that runs a query" do
        GenServer.call(MyApp.Worker, :run_query)
      end

  By calling `mode({:shared, self()})`, any process that needs
  to talk to the database will now use the same connection as the
  one checked out by the test process during the `setup` block.

  Make sure to always check a connection out before setting the mode
  to `{:shared, self()}`.

  The advantage of shared mode is that by calling a single function,
  you will ensure all upcoming processes and operations will use that
  shared connection, without a need to explicitly allow them. The
  downside is that tests can no longer run concurrently in shared mode.

  Also, beware that if the test process terminates while the worker is
  using the connection, the connection will be taken away from the worker,
  which will error. Therefore it is important to guarantee the work is done
  before the test concludes. In the example above, we are using a `call`,
  which is synchronous, avoiding the problem, but you may need to explicitly
  flush the worker or terminate it under such scenarios in your tests.

  ### Summing up

  There are two mechanisms for explicit ownerships:

    * Using allowances - requires explicit allowances via `allow/3`.
      Tests may run concurrently.

    * Using shared mode - does not require explicit allowances.
      Tests cannot run concurrently.

  ## FAQ

  When running the sandbox mode concurrently, developers may run into
  issues we explore in the upcoming sections.

  ### "owner exited"

  In some situations, you may see error reports similar to the one below:

      23:59:59.999 [error] Postgrex.Protocol (#PID<>) disconnected:
          ** (DBConnection.Error) owner #PID<> exited
      Client #PID<> is still using a connection from owner

  Such errors are usually followed by another error report from another
  process that failed while executing a database query.

  To understand the failure, we need to answer the question: who are the
  owner and client processes? The owner process is the one that checks
  out the connection, which, in the majority of cases, is the test process,
  the one running your tests. In other words, the error happens because
  the test process has finished, either because the test succeeded or
  because it failed, while the client process was trying to get information
  from the database. Since the owner process, the one that owns the
  connection, no longer exists, Ecto will check the connection back in
  and notify the client process using the connection that the connection
  owner is no longer available.

  This can happen in different situations. For example, imagine you query
  a GenServer in your test that is using a database connection:

      test "gets results from GenServer" do
        {:ok, pid} = MyAppServer.start_link()
        Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
        assert MyAppServer.get_my_data_fast(timeout: 1000) == [...]
      end

  In the test above, we spawn the server and allow it to perform database
  queries using the connection owned by the test process. Since we gave
  a timeout of 1 second, in case the database takes longer than one second
  to reply, the test process will fail, due to the timeout, making the
  "owner down" message to be printed because the server process is still
  waiting on a connection reply.

  In some situations, such failures may be intermittent. Imagine that you
  allow a process that queries the database every half second:

      test "queries periodically" do
        {:ok, pid} = PeriodicServer.start_link()
        Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
        # assertions
      end

  Because the server is querying the database from time to time, there is
  a chance that, when the test exits, the periodic process may be querying
  the database, regardless of test success or failure.

  To address this, you can tell ExUnit to manage your processes:

      test "queries periodically" do
        pid = start_supervised!(PeriodicServer)
        Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
        # assertions
      end

  By using `start_supervised!/1`, ExUnit guarantees the process finishes
  before your test (the connection owner).

  In some situations, however, the dynamic processes are directly started
  inside a `DynamicSupervisor` or a `Task.Supervisor`. You can guarantee
  proper termination in such scenarios by adding an `on_exit` callback
  that waits until all supervised children terminate:

      on_exit(fn ->
        for {_, pid, _, _} <- DynamicSupervisor.which_children(MyApp.DynamicSupervisor) do
          ref = Process.monitor(pid)
          assert_receive {:DOWN, ^ref, _, _, _}, :infinity
        end
      end)

  ### "owner timed out because it owned the connection for longer than Nms"

  In some situations, you may see error reports similar to the one below:

      09:56:43.081 [error] Postgrex.Protocol (#PID<>) disconnected:
          ** (DBConnection.ConnectionError) owner #PID<> timed out
          because it owned the connection for longer than 120000ms

  If you have a long running test (or you're debugging with IEx.pry),
  the timeout for the connection ownership may be too short.  You can
  increase the timeout by setting the `:ownership_timeout` options for
  your repo config in `config/config.exs` (or preferably in `config/test.exs`):

      config :my_app, MyApp.Repo,
        ownership_timeout: NEW_TIMEOUT_IN_MILLISECONDS

  The `:ownership_timeout` option is part of `DBConnection.Ownership`
  and defaults to 120000ms. Timeouts are given as integers in milliseconds.

  Alternately, if this is an issue for only a handful of long-running tests,
  you can pass an `:ownership_timeout` option when calling
  `Ecto.Adapters.SQL.Sandbox.checkout/2` instead of setting a longer timeout
  globally in your config.

  ### Deferred constraints

  Some databases allow to defer constraint validation to the transaction
  commit time, instead of the particular statement execution time. This
  feature, for instance, allows for a cyclic foreign key referencing.
  Since the SQL Sandbox mode rolls back transactions, tests might report
  false positives because deferred constraints are never checked by the
  database. To manually force deferred constraints validation when using
  PostgreSQL use the following line right at the end of your test case:

      Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")

  ### Database locks and deadlocks

  Since the sandbox relies on concurrent transactional tests, there is
  a chance your tests may trigger deadlocks in your database. This is
  specially true with MySQL, where the solutions presented here are not
  enough to avoid deadlocks and therefore making the use of concurrent tests
  with MySQL prohibited.

  However, even on databases like PostgreSQL, performance degradations or
  deadlocks may still occur. For example, imagine a "users" table with a
  unique index on the "email" column. Now consider multiple tests are
  trying to insert the same user email to the database. They will attempt
  to retrieve the same database lock, causing only one test to succeed and
  run while all other tests wait for the lock.

  In other situations, two different tests may proceed in a way that
  each test retrieves locks desired by the other, leading to a situation
  that cannot be resolved, a deadlock. For instance:

  ```text
  Transaction 1:                Transaction 2:
  begin
                                begin
  update posts where id = 1
                                update posts where id = 2
                                update posts where id = 1
  update posts where id = 2
                        **deadlock**
  ```

  There are different ways to avoid such problems. One of them is
  to make sure your tests work on distinct data. Regardless of
  your choice between using fixtures or factories for test data,
  make sure you get a new set of data per test. This is specially
  important for data that is meant to be unique like user emails.

  For example, instead of:

      def insert_user do
        Repo.insert!(%User{email: "sample@example.com"})
      end

  prefer:

      def insert_user do
        Repo.insert!(%User{email: "sample-#{counter()}@example.com"})
      end

      defp counter do
        System.unique_integer([:positive])
      end

  In fact, avoiding unique emails like above can also have a positive
  impact on the test suite performance, as it reduces contention and
  wait between concurrent tests. We have heard reports where using
  dynamic values for uniquely indexed columns, as we did for email
  above, made a test suite run between 2x to 3x faster.

  Deadlocks may happen in other circumstances. If you believe you
  are hitting a scenario that has not been described here, please
  report an issue so we can improve our examples. As a last resort,
  you can always disable the test triggering the deadlock from
  running asynchronously by setting  "async: false".
  """

  defmodule Connection do
    @moduledoc false
    if Code.ensure_loaded?(DBConnection) do
      @behaviour DBConnection
    end

    def connect(_opts) do
      raise "should never be invoked"
    end

    def disconnect(err, {conn_mod, state, _in_transaction?}) do
      conn_mod.disconnect(err, state)
    end

    def checkout(state), do: proxy(:checkout, state, [])
    def checkin(state), do: proxy(:checkin, state, [])
    def ping(state), do: proxy(:ping, state, [])

    def handle_begin(opts, {conn_mod, state, false}) do
      opts = [mode: :savepoint] ++ opts

      case conn_mod.handle_begin(opts, state) do
        {:ok, value, state} ->
          {:ok, value, {conn_mod, state, true}}

        {kind, err, state} ->
          {kind, err, {conn_mod, state, false}}
      end
    end

    def handle_commit(opts, {conn_mod, state, true}) do
      opts = [mode: :savepoint] ++ opts
      proxy(:handle_commit, {conn_mod, state, false}, [opts])
    end

    def handle_rollback(opts, {conn_mod, state, _}) do
      opts = [mode: :savepoint] ++ opts
      proxy(:handle_rollback, {conn_mod, state, false}, [opts])
    end

    def handle_status(opts, state),
      do: proxy(:handle_status, state, [maybe_savepoint(opts, state)])

    def handle_prepare(query, opts, state),
      do: proxy(:handle_prepare, state, [query, maybe_savepoint(opts, state)])

    def handle_execute(query, params, opts, state),
      do: proxy(:handle_execute, state, [query, params, maybe_savepoint(opts, state)])

    def handle_close(query, opts, state),
      do: proxy(:handle_close, state, [query, maybe_savepoint(opts, state)])

    def handle_declare(query, params, opts, state),
      do: proxy(:handle_declare, state, [query, params, maybe_savepoint(opts, state)])

    def handle_fetch(query, cursor, opts, state),
      do: proxy(:handle_fetch, state, [query, cursor, maybe_savepoint(opts, state)])

    def handle_deallocate(query, cursor, opts, state),
      do: proxy(:handle_deallocate, state, [query, cursor, maybe_savepoint(opts, state)])

    defp maybe_savepoint(opts, {_, _, in_transaction?}) do
      if not in_transaction? and Keyword.get(opts, :sandbox_subtransaction, true) do
        [mode: :savepoint] ++ opts
      else
        opts
      end
    end

    defp proxy(fun, {conn_mod, state, in_transaction?}, args) do
      result = apply(conn_mod, fun, args ++ [state])
      pos = :erlang.tuple_size(result)
      :erlang.setelement(pos, result, {conn_mod, :erlang.element(pos, result), in_transaction?})
    end
  end

  @doc """
  Starts a process that will check out and own a connection, then returns that process's pid.

  The process is not linked to the caller, so it is your responsibility to ensure that it will be
  stopped with `stop_owner/1`. In tests, this is done in  an `ExUnit.Callbacks.on_exit/2` callback:

      setup tags do
        pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MyApp.Repo, shared: not tags[:async])
        on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
        :ok
      end

  ## `start_owner!/2` vs `checkout/2`

  `start_owner!/2` should be used in place of `checkout/2`.

  `start_owner!/2` solves the problem of unlinked processes started in a test outliving the test process and causing ownership errors.
  For example, `LiveView`'s `live(...)` test helper starts a process linked to the LiveView supervisor, not the test process.
  These errors can be eliminated by having the owner of the connection be a separate process from the test process.

  Outside of that scenario, `checkout/2` involves less overhead than this function and so can be preferable.

  ## Options

    * `:shared` - if `true`, the pool runs in the shared mode. Defaults to `false`

  The remaining options are passed to `checkout/2`.
  """
  @doc since: "3.4.4"
  @spec start_owner!(Ecto.Repo.t() | pid(), keyword()) :: pid()
  def start_owner!(repo, opts \\ []) do
    parent = self()

    {:ok, pid} =
      Agent.start(fn ->
        {shared, opts} = Keyword.pop(opts, :shared, false)
        :ok = checkout(repo, opts)

        if shared do
          :ok = mode(repo, {:shared, self()})
        else
          :ok = allow(repo, self(), parent)
        end
      end)

    pid
  end

  @doc """
  Stops an owner process started by `start_owner!/2`.
  """
  @doc since: "3.4.4"
  @spec stop_owner(pid()) :: :ok
  def stop_owner(pid) do
    GenServer.stop(pid)
  end

  @doc """
  Sets the mode for the `repo` pool.

  The modes can be:

    * `:auto` - this is the default mode. When trying to use the repository,
      processes can automatically checkout a connection without calling
      `checkout/2` or `start_owner/2` before. This is the mode you will run
      on before your test suite starts

    * `:manual` - in this mode, the connection always has to be explicitly
      checked before used. Other processes are allowed to use the same
      connection if they are explicitly allowed via `allow/4`. You usually
      set the mode to manual at the end of your `test/test_helper.exs` file.
      This is also the mode you will run your async tests in

    * `{:shared, pid}` - after checking out a connection in manual mode,
      you can change the mode to `{:shared, pid}`, where pid is the process
      that owns the connection, most often `{:shared, self()}`. This makes it
      so all processes can use the same connection as the one owned by the
      current process. This is the mode you will run your sync tests in

  Whenever you change the mode to `:manual` or `:auto`, all existing
  connections are checked in. Therefore, it is recommend to set those
  modes before your test suite starts, as otherwise you will check in
  connections being used in any other test running concurrently.

  If successful, returns `:ok` (this is always successful for `:auto`
  and `:manual` modes). It may return `:not_owner` or `:not_found`
  when setting `{:shared, pid}` and the given `pid` does not own any
  connection for the repo. May return `:already_shared` if another
  process set the ownership mode to `{:shared, _}` and is still alive.
  """
  @spec mode(Ecto.Repo.t() | pid(), :auto | :manual | {:shared, pid()}) ::
          :ok | :already_shared | :not_owner | :not_found
  def mode(repo, mode)
      when (is_atom(repo) or is_pid(repo)) and mode in [:auto, :manual]
      when (is_atom(repo) or is_pid(repo)) and elem(mode, 0) == :shared and is_pid(elem(mode, 1)) do
    %{pid: pool, opts: opts} = lookup_meta!(repo)
    DBConnection.Ownership.ownership_mode(pool, mode, opts)
  end

  @doc """
  Checks a connection out for the given `repo`.

  The process calling `checkout/2` will own the connection
  until it calls `checkin/2` or until it crashes in which case
  the connection will be automatically reclaimed by the pool.

  If successful, returns `:ok`. If the caller already has a
  connection, it returns `{:already, :owner | :allowed}`.

  ## Options

    * `:sandbox` - when true the connection is wrapped in
      a transaction. Defaults to true.

    * `:isolation` - set the query to the given isolation level.

    * `:ownership_timeout` - limits how long the connection can be
      owned. Defaults to the value in your repo config in
      `config/config.exs` (or preferably in `config/test.exs`), or
      120000 ms if not set. The timeout exists for sanity checking
      purposes, to ensure there is no connection leakage, and can
      be bumped whenever necessary.

  """
  @spec checkout(Ecto.Repo.t() | pid(), keyword()) :: :ok | {:already, :owner | :allowed}
  def checkout(repo, opts \\ []) when is_atom(repo) or is_pid(repo) do
    %{pid: pool, opts: pool_opts} = lookup_meta!(repo)

    pool_opts =
      if Keyword.get(opts, :sandbox, true) do
        [
          post_checkout: &post_checkout(&1, &2, opts),
          pre_checkin: &pre_checkin(&1, &2, &3, opts)
        ] ++ pool_opts
      else
        pool_opts
      end

    pool_opts_overrides = Keyword.take(opts, [:ownership_timeout, :isolation_level])
    pool_opts = Keyword.merge(pool_opts, pool_opts_overrides)

    case DBConnection.Ownership.ownership_checkout(pool, pool_opts) do
      :ok ->
        if isolation = opts[:isolation] do
          set_transaction_isolation_level(repo, isolation)
        end

        :ok

      other ->
        other
    end
  end

  defp set_transaction_isolation_level(repo, isolation) do
    query = "SET TRANSACTION ISOLATION LEVEL #{isolation}"

    case Ecto.Adapters.SQL.query(repo, query, [], sandbox_subtransaction: false) do
      {:ok, _} ->
        :ok

      {:error, error} ->
        checkin(repo, [])
        raise error
    end
  end

  @doc """
  Checks in the connection back into the sandbox pool.
  """
  @spec checkin(Ecto.Repo.t() | pid()) :: :ok | :not_owner | :not_found
  def checkin(repo, _opts \\ []) when is_atom(repo) or is_pid(repo) do
    %{pid: pool, opts: opts} = lookup_meta!(repo)
    DBConnection.Ownership.ownership_checkin(pool, opts)
  end

  @doc """
  Allows the `allow` process to use the same connection as `parent`.

  `allow` may be a PID or a locally registered name.

  If the allowance is successful, this function returns `:ok`. If `allow` is already an
  owner or already allowed, it returns `{:already, :owner | :allowed}`. If `parent` has not
  checked out a connection from the repo, it returns `:not_found`.
  """
  @spec allow(Ecto.Repo.t() | pid(), pid(), term()) ::
          :ok | {:already, :owner | :allowed} | :not_found
  def allow(repo, parent, allow, opts \\ []) when is_atom(repo) or is_pid(repo) do
    case GenServer.whereis(allow) do
      pid when is_pid(pid) ->
        %{pid: pool, opts: meta_opts} = lookup_meta!(repo)
        opts = Keyword.merge(meta_opts, opts)
        DBConnection.Ownership.ownership_allow(pool, parent, pid, opts)

      other ->
        raise """
        only PID or a locally registered process can be allowed to \
        use the same connection as parent but the lookup returned #{inspect(other)}
        """
    end
  end

  @doc """
  Runs a function outside of the sandbox.
  """
  @spec unboxed_run(Ecto.Repo.t() | pid(), (-> result)) :: result when result: var
  def unboxed_run(repo, fun) when is_atom(repo) or is_pid(repo) do
    checkin(repo)
    checkout(repo, sandbox: false)

    try do
      fun.()
    after
      checkin(repo)
    end
  end

  defp lookup_meta!(repo) do
    %{opts: opts} =
      meta =
      repo
      |> find_repo()
      |> Ecto.Adapter.lookup_meta()

    if opts[:pool] != DBConnection.Ownership do
      raise """
      cannot invoke sandbox operation with pool #{inspect(opts[:pool])}.
      To use the SQL Sandbox, configure your repository pool as:

          pool: #{inspect(__MODULE__)}
      """
    end

    meta
  end

  defp find_repo(repo) when is_atom(repo), do: repo.get_dynamic_repo()
  defp find_repo(repo), do: repo

  defp post_checkout(conn_mod, conn_state, opts) do
    case conn_mod.handle_begin([mode: :transaction] ++ opts, conn_state) do
      {:ok, _, conn_state} ->
        {:ok, Connection, {conn_mod, conn_state, false}}

      {:transaction, _conn_state} ->
        raise """
        Ecto SQL sandbox transaction cannot be started because there is already\
        a transaction running.

        This either means some code is starting a transaction before the sandbox\
        or a connection was not appropriately rolled back after use.
        """

      {_error_or_disconnect, err, conn_state} ->
        {:disconnect, err, conn_mod, conn_state}
    end
  end

  defp pre_checkin(:checkin, Connection, {conn_mod, conn_state, _in_transaction?}, opts) do
    case conn_mod.handle_rollback([mode: :transaction] ++ opts, conn_state) do
      {:ok, _, conn_state} ->
        {:ok, conn_mod, conn_state}

      {:idle, _conn_state} ->
        raise """
        Ecto SQL sandbox transaction was already committed/rolled back.

        The sandbox works by running each test in a transaction and closing the\
        transaction afterwards. However, the transaction has already terminated.\
        Your test code is likely committing or rolling back transactions manually,\
        either by invoking procedures or running custom SQL commands.

        One option is to manually checkout a connection without a sandbox:

            Ecto.Adapters.SQL.Sandbox.checkout(repo, sandbox: false)

        But remember you will have to undo any database changes performed by such tests.
        """

      {_error_or_disconnect, err, conn_state} ->
        {:disconnect, err, conn_mod, conn_state}
    end
  end

  defp pre_checkin(_, Connection, {conn_mod, conn_state, _in_transaction?}, _opts) do
    {:ok, conn_mod, conn_state}
  end
end
