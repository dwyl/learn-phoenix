defmodule DBConnection.Pool do
  @moduledoc false

  @type pool :: GenServer.server()
  @type connection_metrics :: %{
          source: {:pool | :proxy, pid()},
          ready_conn_count: non_neg_integer(),
          checkout_queue_length: non_neg_integer()
        }

  @callback disconnect_all(pool, interval :: term, options :: keyword) :: :ok

  @callback checkout(pool, callers :: [pid], options :: keyword) ::
              {:ok, pool_ref :: term, module, checkin_time :: non_neg_integer() | nil,
               state :: term}
              | {:error, Exception.t()}

  @callback get_connection_metrics(pool :: pool()) :: [connection_metrics()]
end
