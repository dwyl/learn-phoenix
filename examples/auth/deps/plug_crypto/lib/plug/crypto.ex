defmodule Plug.Crypto do
  @moduledoc """
  Namespace and module for crypto-related functionality.

  For low-level functionality, see `Plug.Crypto.KeyGenerator`,
  `Plug.Crypto.MessageEncryptor`, and `Plug.Crypto.MessageVerifier`.
  """

  alias Plug.Crypto.{KeyGenerator, MessageVerifier, MessageEncryptor}

  @doc """
  Prunes the stacktrace to remove any argument trace.

  This is useful when working with functions that receives secrets
  and we want to make sure those secrets do not leak on error messages.
  """
  @spec prune_args_from_stacktrace(Exception.stacktrace()) :: Exception.stacktrace()
  def prune_args_from_stacktrace(stacktrace)

  def prune_args_from_stacktrace([{mod, fun, [_ | _] = args, info} | rest]),
    do: [{mod, fun, length(args), info} | rest]

  def prune_args_from_stacktrace(stacktrace) when is_list(stacktrace),
    do: stacktrace

  @doc """
  A restricted version of `:erlang.binary_to_term/2` that forbids
  *executable* terms, such as anonymous functions.

  The `opts` are given to the underlying `:erlang.binary_to_term/2`
  call, with an empty list as a default.

  By default this function does not restrict atoms, as an atom
  interned in one node may not yet have been interned on another
  (except for releases, which preload all code).

  If you want to avoid atoms from being created, then you can pass
  `[:safe]` as options, as that will also enable the safety mechanisms
  from `:erlang.binary_to_term/2` itself.
  """
  @spec non_executable_binary_to_term(binary(), [atom()]) :: term()
  def non_executable_binary_to_term(binary, opts \\ []) when is_binary(binary) do
    term = :erlang.binary_to_term(binary, opts)
    non_executable_terms(term)
    term
  end

  defp non_executable_terms(list) when is_list(list) do
    non_executable_list(list)
  end

  defp non_executable_terms(tuple) when is_tuple(tuple) do
    non_executable_tuple(tuple, tuple_size(tuple))
  end

  defp non_executable_terms(map) when is_map(map) do
    folder = fn key, value, acc ->
      non_executable_terms(key)
      non_executable_terms(value)
      acc
    end

    :maps.fold(folder, map, map)
  end

  defp non_executable_terms(other)
       when is_atom(other) or is_number(other) or is_bitstring(other) or is_pid(other) or
              is_reference(other) do
    other
  end

  defp non_executable_terms(other) do
    raise ArgumentError,
          "cannot deserialize #{inspect(other)}, the term is not safe for deserialization"
  end

  defp non_executable_list([]), do: :ok

  defp non_executable_list([h | t]) when is_list(t) do
    non_executable_terms(h)
    non_executable_list(t)
  end

  defp non_executable_list([h | t]) do
    non_executable_terms(h)
    non_executable_terms(t)
  end

  defp non_executable_tuple(_tuple, 0), do: :ok

  defp non_executable_tuple(tuple, n) do
    non_executable_terms(:erlang.element(n, tuple))
    non_executable_tuple(tuple, n - 1)
  end

  @doc """
  Masks the token on the left with the token on the right.

  Both tokens are required to have the same size.
  """
  @spec mask(binary(), binary()) :: binary()
  def mask(left, right) do
    :crypto.exor(left, right)
  end

  @doc """
  Compares the two binaries (one being masked) in constant-time to avoid
  timing attacks.

  It is assumed the right token is masked according to the given mask.
  """
  @spec masked_compare(binary(), binary(), binary()) :: boolean()
  def masked_compare(left, right, mask)
      when is_binary(left) and is_binary(right) and is_binary(mask) do
    byte_size(left) == byte_size(right) and byte_size(right) == byte_size(mask) and
      crypto_exor_hash_equals(left, right, mask)
  end

  defp crypto_exor_hash_equals(x, y, z) do
    crypto_hash_equals(mask(x, y), z)
  end

  @doc """
  Compares the two binaries in constant-time to avoid timing attacks.

  See: http://codahale.com/a-lesson-in-timing-attacks/
  """
  @spec secure_compare(binary(), binary()) :: boolean()
  def secure_compare(left, right) when is_binary(left) and is_binary(right) do
    byte_size(left) == byte_size(right) and crypto_hash_equals(left, right)
  end

  # TODO: remove when we require OTP 25.0
  if Code.ensure_loaded?(:crypto) and function_exported?(:crypto, :hash_equals, 2) do
    defp crypto_hash_equals(x, y) do
      # Depending on the linked OpenSSL library hash_equals is available.
      # If not, we fall back to the legacy implementation.
      try do
        :crypto.hash_equals(x, y)
      rescue
        # Still can throw "Unsupported CRYPTO_memcmp"
        ErlangError ->
          legacy_secure_compare(x, y, 0)
      end
    end
  else
    defp crypto_hash_equals(x, y) do
      legacy_secure_compare(x, y, 0)
    end
  end

  defp legacy_secure_compare(<<x, left::binary>>, <<y, right::binary>>, acc) do
    import Bitwise
    xorred = bxor(x, y)
    legacy_secure_compare(left, right, acc ||| xorred)
  end

  defp legacy_secure_compare(<<>>, <<>>, acc) do
    acc === 0
  end

  @doc """
  Encodes and signs data into a token you can send to clients.

      Plug.Crypto.sign(conn.secret_key_base, "user-secret", {:elixir, :terms})

  A key will be derived from the secret key base and the given user secret.
  The key will also be cached for performance reasons on future calls.

  ## Options

    * `:key_iterations` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to 1000
    * `:key_length` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to 32
    * `:key_digest` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to `:sha256`
    * `:signed_at` - set the timestamp of the token in seconds.
      Defaults to `System.os_time(:millisecond)`
    * `:max_age` - the default maximum age of the token. Defaults to
      `86400` seconds (1 day) and it may be overridden on `verify/4`.

  """
  def sign(key_base, salt, data, opts \\ []) when is_binary(key_base) and is_binary(salt) do
    data
    |> encode(opts)
    |> MessageVerifier.sign(get_secret(key_base, salt, opts))
  end

  @doc """
  Encodes, encrypts, and signs data into a token you can send to clients.

      Plug.Crypto.encrypt(conn.secret_key_base, "user-secret", {:elixir, :terms})

  A key will be derived from the secret key base and the given user secret.
  The key will also be cached for performance reasons on future calls.

  ## Options

    * `:key_iterations` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to 1000
    * `:key_length` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to 32
    * `:key_digest` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to `:sha256`
    * `:signed_at` - set the timestamp of the token in seconds.
      Defaults to `System.os_time(:millisecond)`
    * `:max_age` - the default maximum age of the token. Defaults to
      `86400` seconds (1 day) and it may be overridden on `decrypt/4`.

  """
  def encrypt(key_base, secret, data, opts \\ [])
      when is_binary(key_base) and is_binary(secret) do
    data
    |> encode(opts)
    |> MessageEncryptor.encrypt(get_secret(key_base, secret, opts), "")
  end

  defp encode(data, opts) do
    signed_at_seconds = Keyword.get(opts, :signed_at)
    signed_at_ms = if signed_at_seconds, do: trunc(signed_at_seconds * 1000), else: now_ms()
    max_age_in_seconds = Keyword.get(opts, :max_age, 86400)
    :erlang.term_to_binary({data, signed_at_ms, max_age_in_seconds})
  end

  @doc """
  Decodes the original data from the token and verifies its integrity.

  ## Examples

  In this scenario we will create a token, sign it, then provide it to a client
  application. The client will then use this token to authenticate requests for
  resources from the server. See `Plug.Crypto` summary for more info about
  creating tokens.

      iex> user_id    = 99
      iex> secret     = "kjoy3o1zeidquwy1398juxzldjlksahdk3"
      iex> user_salt  = "user salt"
      iex> token      = Plug.Crypto.sign(secret, user_salt, user_id)

  The mechanism for passing the token to the client is typically through a
  cookie, a JSON response body, or HTTP header. For now, assume the client has
  received a token it can use to validate requests for protected resources.

  When the server receives a request, it can use `verify/4` to determine if it
  should provide the requested resources to the client:

      iex> Plug.Crypto.verify(secret, user_salt, token, max_age: 86400)
      {:ok, 99}

  In this example, we know the client sent a valid token because `verify/4`
  returned a tuple of type `{:ok, user_id}`. The server can now proceed with
  the request.

  However, if the client had sent an expired or otherwise invalid token
  `verify/4` would have returned an error instead:

      iex> Plug.Crypto.verify(secret, user_salt, expired, max_age: 86400)
      {:error, :expired}

      iex> Plug.Crypto.verify(secret, user_salt, invalid, max_age: 86400)
      {:error, :invalid}

  ## Options

    * `:max_age` - verifies the token only if it has been generated
      "max age" ago in seconds. Defaults to the max age signed in the
      token (86400)
    * `:key_iterations` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to 1000
    * `:key_length` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to 32
    * `:key_digest` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to `:sha256`

  """
  def verify(key_base, salt, token, opts \\ [])

  def verify(key_base, salt, token, opts)
      when is_binary(key_base) and is_binary(salt) and is_binary(token) do
    secret = get_secret(key_base, salt, opts)

    case MessageVerifier.verify(token, secret) do
      {:ok, message} -> decode(message, opts)
      :error -> {:error, :invalid}
    end
  end

  def verify(_key_base, salt, nil, _opts) when is_binary(salt) do
    {:error, :missing}
  end

  @doc """
  Decrypts the original data from the token and verifies its integrity.

  ## Options

    * `:max_age` - verifies the token only if it has been generated
      "max age" ago in seconds. A reasonable value is 1 day (86400
      seconds)
    * `:key_iterations` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to 1000
    * `:key_length` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to 32
    * `:key_digest` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to `:sha256`

  """
  def decrypt(key_base, secret, token, opts \\ [])

  def decrypt(key_base, secret, nil, opts)
      when is_binary(key_base) and is_binary(secret) and is_list(opts) do
    {:error, :missing}
  end

  def decrypt(key_base, secret, token, opts)
      when is_binary(key_base) and is_binary(secret) and is_list(opts) do
    secret = get_secret(key_base, secret, opts)

    case MessageEncryptor.decrypt(token, secret, "") do
      {:ok, message} -> decode(message, opts)
      :error -> {:error, :invalid}
    end
  end

  defp decode(message, opts) do
    {data, signed, max_age} =
      case non_executable_binary_to_term(message) do
        {data, signed, max_age} -> {data, signed, max_age}
        # For backwards compatibility with Plug.Crypto v1.1
        {data, signed} -> {data, signed, 86400}
        # For backwards compatibility with Phoenix which had the original code
        %{data: data, signed: signed} -> {data, signed, 86400}
      end

    if expired?(signed, Keyword.get(opts, :max_age, max_age)) do
      {:error, :expired}
    else
      {:ok, data}
    end
  end

  ## Helpers

  # Gathers configuration and generates the key secrets and signing secrets.
  defp get_secret(secret_key_base, salt, opts) do
    iterations = Keyword.get(opts, :key_iterations, 1000)
    length = Keyword.get(opts, :key_length, 32)
    digest = Keyword.get(opts, :key_digest, :sha256)
    cache = Keyword.get(opts, :cache, Plug.Crypto.Keys)
    KeyGenerator.generate(secret_key_base, salt, iterations, length, digest, cache)
  end

  defp expired?(_signed, :infinity), do: false
  defp expired?(_signed, max_age_secs) when max_age_secs <= 0, do: true
  defp expired?(signed, max_age_secs), do: signed + trunc(max_age_secs * 1000) < now_ms()

  defp now_ms, do: System.os_time(:millisecond)
end
