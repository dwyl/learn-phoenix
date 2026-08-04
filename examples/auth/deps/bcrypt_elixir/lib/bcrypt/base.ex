defmodule Bcrypt.Base do
  @moduledoc """
  Base module for the Bcrypt password hashing library.
  """

  @compile {:autoload, false}
  @on_load {:init, 0}

  def init do
    case load_nif() do
      :ok ->
        :ok

      _ ->
        raise """
        An error occurred when loading Bcrypt.
        Make sure you have a C compiler and Erlang 20 installed.
        If you are not using Erlang 20, either upgrade to Erlang 20 or
        use version 0.12 of bcrypt_elixir.
        See the Comeonin wiki for more information.
        """
    end
  end

  @doc """
  Generate a salt for use with the `hash_password` function.

  The `:log_rounds` parameter determines the computational complexity
  of the generation of the password hash. Its default is 12, the minimum is 4,
  and the maximum is 31.

  The `:legacy` option is for generating salts with the old `$2a$` prefix.
  Only use this option if you need to generate hashes that are then checked
  by older libraries.
  """
  def gen_salt(log_rounds \\ 12, legacy \\ false) do
    gensalt_nif(:crypto.strong_rand_bytes(16), log_rounds, (legacy and 97) || 98)
  end

  @doc """
  Hash a password using Bcrypt.
  """
  def hash_password(password, salt) when byte_size(salt) == 29 do
    hash(password, salt, :binary.part(salt, 1, 2))
  end

  def hash_password(_, salt) do
    raise ArgumentError, "The salt #{salt} must be 29 bytes long"
  end

  @doc """
  Generate a salt for use with Bcrypt.
  """
  def gensalt_nif(random, log_rounds, minor)
  def gensalt_nif(_, _, _), do: :erlang.nif_error(:not_loaded)

  @doc """
  Hash the password and salt with the Bcrypt hashing algorithm.
  """
  def hash_nif(password, salt)
  def hash_nif(_, _), do: :erlang.nif_error(:not_loaded)

  @doc """
  Verify the password by comparing it with the stored hash.
  """
  def checkpass_nif(password, stored_hash)
  def checkpass_nif(_, _), do: :erlang.nif_error(:not_loaded)

  defp load_nif do
    path = :filename.join(:code.priv_dir(:bcrypt_elixir), ~c"bcrypt_nif")
    :erlang.load_nif(path, 0)
  end

  defp hash(password, salt, prefix) when prefix in ["2a", "2b"] do
    hash_nif(:binary.bin_to_list(password), :binary.bin_to_list(salt))
  end

  defp hash(_, _, prefix) do
    raise ArgumentError, """
    This version of Bcrypt does not support the #{prefix} prefix.
    For more information, see the Bcrypt versions section in the Comeonin wiki,
    at https://github.com/riverrun/comeonin/wiki/Choosing-the-password-hashing-algorithm.
    """
  end
end
