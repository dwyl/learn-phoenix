defprotocol DBConnection.Query do
  @moduledoc """
  The `DBConnection.Query` protocol is responsible for preparing and
  encoding queries.

  All `DBConnection.Query` functions are executed in the caller process which
  means it's safe to, for example, raise exceptions or do blocking calls as
  they won't affect the connection process.
  """

  @doc """
  Parse a query.

  This function is called to parse a query term before it is prepared using a
  connection callback module.

  See `DBConnection.prepare/3`.
  """
  @spec parse(any, Keyword.t()) :: any
  def parse(query, opts)

  @doc """
  Describe a query.

  This function is called to describe a query after it is prepared using a
  connection callback module.

  See `DBConnection.prepare/3`.
  """
  @spec describe(any, Keyword.t()) :: any
  def describe(query, opts)

  @doc """
  Encode parameters using a query.

  This function is called to encode a query before it is executed using a
  connection callback module.

  If this function raises `DBConnection.EncodeError`, then the query is
  prepared once again.

  See `DBConnection.execute/3`.
  """
  @spec encode(any, any, Keyword.t()) :: any
  def encode(query, params, opts)

  @doc """
  Decode a result using a query.

  This function is called to decode a result after it is returned by a
  connection callback module.

  See `DBConnection.execute/3`.
  """
  @spec decode(any, any, Keyword.t()) :: any
  def decode(query, result, opts)
end
