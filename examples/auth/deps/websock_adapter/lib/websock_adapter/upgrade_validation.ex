defmodule WebSockAdapter.UpgradeValidation do
  @moduledoc """
  Provides validation of WebSocket upgrade requests as described in RFC6455§4.2 & RFC8441§5

  The `validate_upgrade/1` function is called internally by `WebSockAdapter.upgrade/4`; there is
  no need to call it yourself before attempting an upgrade (though doing so is harmless)
  """

  # credo:disable-for-this-file Credo.Check.Refactor.RedundantWithClauseResult
  # credo:disable-for-this-file Credo.Check.Design.AliasUsage

  @doc """
  Validates that the request satisfies the requirements to issue a WebSocket upgrade response.

  Validations are performed based on the clauses laid out in RFC6455§4.2 & RFC8441§5

  This function does not actually perform an upgrade or change the connection in any way.
  Regardless of whether or not this function indicates a satisfactory connection, the
  underlying web server MAY still choose to not perform the upgrade (this scenario likely
  indicates a discrepancy between the validations done here and those done in the underlying web
  server & would merit further investigation)

  Returns `:ok` if the connection satisfies the requirements for a WebSocket upgrade, and
  `{:error, reason}` if not
  """
  @spec validate_upgrade(Plug.Conn.t()) :: :ok | {:error, String.t()}
  def validate_upgrade(conn) do
    case Plug.Conn.get_http_protocol(conn) do
      :"HTTP/1.1" -> validate_upgrade_http1(conn)
      :"HTTP/2" -> validate_upgrade_http2(conn)
      other -> {:error, "HTTP version #{other} unsupported"}
    end
  end

  @doc """
  Raising variant of `validate_upgrade/1`.

  Returns `:ok` if the connection satisfies the requirements for a WebSocket upgrade, and raises
  a `WebSockAdapter.UpgradeError` error if validation fails.
  """
  @spec validate_upgrade!(Plug.Conn.t()) :: :ok
  def validate_upgrade!(conn) do
    case validate_upgrade(conn) do
      :ok -> :ok
      {:error, reason} -> raise WebSockAdapter.UpgradeError, reason
    end
  end

  # Validate the conn per RFC6455§4.2.1
  defp validate_upgrade_http1(conn) do
    with :ok <- assert_method(conn, "GET"),
         :ok <- assert_header_nonempty(conn, "host"),
         :ok <- assert_header_contains(conn, "connection", "upgrade"),
         :ok <- assert_header_contains(conn, "upgrade", "websocket"),
         :ok <- assert_header_nonempty(conn, "sec-websocket-key"),
         :ok <- assert_header_equals(conn, "sec-websocket-version", "13") do
      :ok
    end
  end

  # Validate the conn per RFC8441§5. Note that pseudo headers are not exposed
  # through Plug so we cannot test for those clauses here
  defp validate_upgrade_http2(conn) do
    with :ok <- assert_method(conn, "CONNECT"),
         :ok <- assert_header_equals(conn, "sec-websocket-version", "13") do
      :ok
    end
  end

  defp assert_method(conn, verb) do
    case conn.method do
      ^verb -> :ok
      other -> {:error, "HTTP method #{other} unsupported"}
    end
  end

  defp assert_header_nonempty(conn, header) do
    case Plug.Conn.get_req_header(conn, header) do
      [] -> {:error, "'#{header}' header is absent"}
      _ -> :ok
    end
  end

  defp assert_header_equals(conn, header, expected) do
    case Plug.Conn.get_req_header(conn, header) |> Enum.map(&String.downcase(&1, :ascii)) do
      [^expected] -> :ok
      value -> {:error, "'#{header}' header must equal '#{expected}', got #{inspect(value)}"}
    end
  end

  defp assert_header_contains(conn, header, needle) do
    haystack = Plug.Conn.get_req_header(conn, header)

    haystack
    |> Enum.flat_map(&Plug.Conn.Utils.list/1)
    |> Enum.any?(&(String.downcase(&1, :ascii) == needle))
    |> case do
      true -> :ok
      false -> {:error, "'#{header}' header must contain '#{needle}', got #{inspect(haystack)}"}
    end
  end
end
