defmodule Bcrypt do
  @moduledoc """
  Elixir wrapper for the Bcrypt password hashing function.

  For a lower-level API, see `Bcrypt.Base`.

  ## Configuration

  The following parameter can be set in the config file:

    * `:log_rounds` - the computational cost as number of log rounds
      * the default is `12` (2^12 rounds)

  If you are hashing passwords in your tests, it can be useful to add
  the following to the `config/test.exs` file:

      # Note: Do not use this value in production
      config :bcrypt_elixir, log_rounds: 4

  ## Bcrypt

  Bcrypt is a key derivation function for passwords designed by Niels Provos
  and David Mazières. Bcrypt is an adaptive function, which means that it can
  be configured to remain slow and resistant to brute-force attacks even as
  computational power increases.

  ### Warning {: .warning}

  Note that bcrypt only hashes the first 72 bytes of the input string.
  If you are using bcrypt to hash data that is secret, such as passwords,
  this will not cause any issues. However, if the string you are hashing
  contains data that is not secret, then the fact that only the first 72 bytes
  are hashed might lead to security issues.

  See https://github.com/riverrun/bcrypt_elixir/issues/51 for more information.

  ## Bcrypt versions

  This bcrypt implementation is based on the latest OpenBSD version, which uses
  the prefix `$2b$`.

  The `$2b$` prefix was used to replace the previous `$2a$` prefix in 2014 when
  a bug affecting passwords longer than 255 bytes was discovered.
  See https://undeadly.org/cgi?action=article&sid=20140224132743 for details.

  For password verification, hashes with either the `$2b$` prefix or the older
  `$2a$` prefix are supported.

  This is not recommended, but to create hashes that use the older `$2a$` prefix,
  you can do so by running the following command:

      Bcrypt.Base.hash_password("hard to guess", Bcrypt.Base.gen_salt(12, true))

  The `$2y$` prefix is not supported, as this prefix was introduced by crypt_blowfish,
  a PHP implementation of bcrypt, and it is not supported by OpenBSD. However,
  if you need to support the `$2y$` prefix, note that, according to https://www.openwall.com/crypt/,
  "the $2b$ prefix ... behaves exactly the same as crypt_blowfish's $2y$",
  and so you could use this library for password verification after replacing
  the `$2y$` prefix of the hashes with `$2b$`.
  """

  use Comeonin

  alias Bcrypt.Base

  @doc """
  Hashes a password with a randomly generated salt.

  ## Option

    * `:log_rounds` - the computational cost as number of log rounds
      * the default is 12 (2^12 rounds)
      * this can be used to override the value set in the config

  ## Examples

  The following examples show how to hash a password with a randomly-generated
  salt and then verify a password:

      iex> hash = Bcrypt.hash_pwd_salt("password")
      ...> Bcrypt.verify_pass("password", hash)
      true

      iex> hash = Bcrypt.hash_pwd_salt("password")
      ...> Bcrypt.verify_pass("incorrect", hash)
      false

  """
  @impl true
  def hash_pwd_salt(password, opts \\ []) do
    Base.hash_password(
      password,
      Base.gen_salt(
        Keyword.get(opts, :log_rounds, Application.get_env(:bcrypt_elixir, :log_rounds, 12)),
        Keyword.get(opts, :legacy, false)
      )
    )
  end

  @doc """
  Verifies a password by hashing the password and comparing the hashed value
  with a stored hash.

  See the documentation for `hash_pwd_salt/2` for examples of using this function.
  """
  @impl true
  def verify_pass(password, stored_hash) do
    Base.checkpass_nif(:binary.bin_to_list(password), :binary.bin_to_list(stored_hash))
    |> handle_verify
  end

  defp handle_verify(0), do: true
  defp handle_verify(_), do: false
end
