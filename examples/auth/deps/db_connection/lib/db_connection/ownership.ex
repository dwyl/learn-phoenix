defmodule DBConnection.OwnershipError do
  @moduledoc """
  An exception for when errors with ownership occur.
  """

  defexception [:message]

  def exception(message), do: %DBConnection.OwnershipError{message: message}
end

defmodule DBConnection.Ownership do
  @moduledoc """
  A DBConnection pool that requires explicit checkout and checkin
  as a mechanism to coordinate between processes.

  ## Options

    * `:ownership_mode` - When mode is `:manual`, all connections must
      be explicitly checked out before by using `ownership_checkout/2`.
      Otherwise, mode is `:auto` and connections are checked out
      implicitly. `{:shared, owner}` mode is also supported so
      processes are allowed on demand. On all cases, checkins are
      explicit via `ownership_checkin/2`. Defaults to `:auto`.
    * `:ownership_timeout` - The maximum time (in milliseconds) that a process
      is allowed to own a connection or `:infinity`, default `120_000`.
      This timeout exists mostly for sanity checking purposes and can be increased
      at will, since DBConnection automatically checks in connections whenever
      there is a mode change.
    * `:ownership_log` - The `Logger.level` to log ownership changes, or `nil`
      not to log, default `nil`.

  There are also two experimental options, `:post_checkout` and `:pre_checkin`
  which allows a developer to configure what happens when a connection is
  checked out and checked in. Those options are meant to be used during tests,
  and have the following behaviour:

    * `:post_checkout` - it must be an anonymous function that receives the
      connection module, the connection state and it must return either
      `{:ok, connection_module, connection_state}` or
      `{:disconnect, err, connection_module, connection_state}`. This allows
      the developer to change the connection module on post checkout. However,
      in case of disconnects, the return `connection_module` must be the same
      as the `connection_module` given. Defaults to simply returning the given
      connection module and state.

    * `:pre_checkin` - it must be an anonymous function that receives the
      checkin reason (`:checkin`, `{:disconnect, err}` or `{:stop, err}`),
      the connection module and the connection state returned by `post_checkout`.
      It must return either `{:ok, connection_module, connection_state}` or
      `{:disconnect, err, connection_module, connection_state}` where the connection
      module is the module given to `:post_checkout` Defaults to simply returning
      the given connection module and state.

  ## Callers lookup

  When checking out, the ownership pool first looks if there is a connection
  assigned to the current process and then checks if there is a connection
  assigned to any of the processes listed under the `$callers` process
  dictionary entry. The `$callers` entry is set by default for tasks from
  Elixir v1.8.

  You can also pass the `:caller` option on checkout with a pid and that
  pid will be looked up first, instead of `self()`, and then we fall back
  to `$callers`.
  """

  alias DBConnection.Ownership.Manager
  alias DBConnection.Holder

  @behaviour DBConnection.Pool

  @doc false
  defdelegate child_spec(args), to: Manager

  @doc false
  @impl DBConnection.Pool
  defdelegate disconnect_all(pool, interval, opts), to: Manager

  @doc false
  @impl DBConnection.Pool
  def checkout(pool, callers, opts) do
    case Manager.proxy_for(callers, opts) do
      {caller, pool} -> Holder.checkout(pool, [caller], opts)
      nil -> Holder.checkout(pool, callers, opts)
    end
  end

  @doc false
  @impl DBConnection.Pool
  defdelegate get_connection_metrics(pool), to: Manager

  @doc """
  Explicitly checks a connection out from the ownership manager.

  It may return `:ok` if the connection is checked out.
  `{:already, :owner | :allowed}` if the caller process already
  has a connection, or raise if there was an error.
  """
  @spec ownership_checkout(GenServer.server(), Keyword.t()) ::
          :ok | {:already, :owner | :allowed}
  def ownership_checkout(manager, opts) do
    with {:ok, pid} <- Manager.checkout(manager, opts) do
      case Holder.checkout(pid, [self()], opts) do
        {:ok, pool_ref, _module, _idle_time, _state} ->
          Holder.checkin(pool_ref)

        {:error, err} ->
          raise err
      end
    end
  end

  @doc """
  Changes the ownership mode.

  `mode` may be `:auto`, `:manual` or `{:shared, owner}`.

  The operation will always succeed when setting the mode to
  `:auto` or `:manual`. It may fail with reason `:not_owner`
  or `:not_found` when setting `{:shared, pid}` and the
  given pid does not own any connection. May return
  `:already_shared` if another process set the ownership
  mode to `{:shared, _}` and is still alive.
  """
  @spec ownership_mode(GenServer.server(), :auto | :manual | {:shared, pid}, Keyword.t()) ::
          :ok | :already_shared | :not_owner | :not_found
  defdelegate ownership_mode(manager, mode, opts), to: Manager, as: :mode

  @doc """
  Checks a connection back in.

  A connection can only be checked back in by its owner.
  """
  @spec ownership_checkin(GenServer.server(), Keyword.t()) ::
          :ok | :not_owner | :not_found
  defdelegate ownership_checkin(manager, opts), to: Manager, as: :checkin

  @doc """
  Allows the process given by `allow` to use the connection checked out
  by `owner_or_allowed`.

  It may return `:ok` if the connection is checked out.
  `{:already, :owner | :allowed}` if the `allow` process already
  has a connection. `owner_or_allowed` may either be the owner or any
  other allowed process. Returns `:not_found` if the given process
  does not have any connection checked out.

  Setting the `unallow_existing` option to `true` will remove the process given by `allow` from
  any existing allowance it may have (this is necessary because a given process can only be
  allowed on a single connection at a time).
  """
  @spec ownership_allow(GenServer.server(), owner_or_allowed :: pid, allow :: pid, Keyword.t()) ::
          :ok | {:already, :owner | :allowed} | :not_found
  defdelegate ownership_allow(manager, owner, allow, opts), to: Manager, as: :allow
end
