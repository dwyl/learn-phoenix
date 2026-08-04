# Bcrypt

[![Build Status](https://travis-ci.com/riverrun/bcrypt_elixir.svg?branch=master)](https://travis-ci.com/riverrun/bcrypt_elixir)
[![Module Version](http://img.shields.io/hexpm/v/bcrypt_elixir.svg)](https://hex.pm/packages/bcrypt_elixir)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/bcrypt_elixir/)
[![Total Download](https://img.shields.io/hexpm/dt/bcrypt_elixir.svg)](https://hex.pm/packages/bcrypt_elixir)
[![License](https://img.shields.io/hexpm/l/bcrypt_elixir.svg)](https://github.com/riverrun/bcrypt_elixir/blob/master/LICENSE)
[![Last Updated](https://img.shields.io/github/last-commit/riverrun/bcrypt_elixir.svg)](https://github.com/riverrun/bcrypt_elixir/commits/master)

Bcrypt password hashing library for Elixir.

Bcrypt is a well-tested password-based key derivation function that
can be configured to remain slow and resistant to brute-force attacks
even as computational power increases.

## Compatibility with other Bcrypt libraries

This version is based on the OpenBSD version of Bcrypt and supports
the `$2b$` and `$2a$` prefixes. For advice on how to use hashes with
the `$2y$` prefix, see [this issue](https://github.com/riverrun/comeonin/issues/103).

## Installation

1.  Add `:bcrypt_elixir` to the `deps` section of your `mix.exs` file:

    If you are using Erlang >20:

    ```elixir
    def deps do
      [
        {:bcrypt_elixir, "~> 3.0"}
      ]
    end
    ```

    If you are using Erlang 19 or below:

    ```elixir
    def deps do
      [
        {:bcrypt_elixir, "~> 0.12"}
      ]
    end
    ```

2.  Make sure you have a C compiler installed.
See the [Comeonin wiki](https://github.com/riverrun/comeonin/wiki/Requirements) for details.

3.  Optional: during tests (and tests only), you may want to reduce the number of rounds
so it does not slow down your test suite. If you have a config/test.exs, you should
add:

    ```elixir
    config :bcrypt_elixir, :log_rounds, 4
    ```

## Comeonin wiki

See the [Comeonin wiki](https://github.com/riverrun/comeonin/wiki) for more
information on the following topics:

* [Algorithms](https://github.com/riverrun/comeonin/wiki/Choosing-the-password-hashing-algorithm)
* [Requirements](https://github.com/riverrun/comeonin/wiki/Requirements)
* [Deployment](https://github.com/riverrun/comeonin/wiki/Deployment)
  * Including information about using Docker
* [References](https://github.com/riverrun/comeonin/wiki/References)

## Contributing

There are many ways you can contribute to the development of this library, including:

* Reporting issues
* Improving documentation
* Sharing your experiences with others

### Documentation

http://hexdocs.pm/bcrypt_elixir

### License

BSD. For full details, please read the LICENSE file.
