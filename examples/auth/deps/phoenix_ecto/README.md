# Phoenix/Ecto

[![Action Status](https://github.com/phoenixframework/phoenix_ecto/workflows/CI/badge.svg)](https://github.com/phoenixframework/phoenix_ecto/actions?query=workflow%3ACI)

A project that integrates [Phoenix](http://github.com/phoenixframework/phoenix) with [Ecto](http://github.com/elixir-lang/ecto), implementing all relevant protocols.

## Installation

You can install `phoenix_ecto` by adding it to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:phoenix_ecto, "~> 4.0"}]
end
```

## The Phoenix <-> Ecto integration

Thanks to Elixir protocols, the integration between Phoenix and Ecto is simply a matter of implementing a handful of protocols. We provide the following implementations:

  * `Phoenix.HTML.FormData` protocol for `Ecto.Changeset`
  * `Phoenix.HTML.Safe` protocol for `Decimal`
  * `Plug.Exception` protocol for the relevant Ecto exceptions

## Concurrent browser tests

This library also provides a plug called `Phoenix.Ecto.SQL.Sandbox` that allows developers to run acceptance tests powered by headless browsers such as ChromeDriver and Selenium concurrently. If you are not familiar with Ecto's SQL sandbox, we recommend you to first get acquainted with it by [reading `Ecto.Adapters.SQL.Sandbox` documentation](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html).

To enable concurrent acceptance tests, make sure you are using PostgreSQL and follow the instructions below:

1. Set a flag to enable the sandbox in `config/test.exs`:

    ```elixir
    config :your_app, sql_sandbox: true
    ```

2. And use the flag to conditionally add the plug to `lib/your_app/endpoint.ex`:

    ```elixir
    if Application.get_env(:your_app, :sql_sandbox) do
      plug Phoenix.Ecto.SQL.Sandbox
    end
    ```

    Make sure that this is placed **before** the line `plug YourApp.Router` (or any other plug that may access the database).

You can now checkout a sandboxed connection and pass the connection information to an acceptance testing tool like [Hound](https://github.com/hashnuke/hound) or [Wallaby](https://github.com/elixir-wallaby/wallaby).

### Hound

To write concurrent acceptance tests with Hound, first add it as a dependency to your `mix.exs`:

```elixir
{:hound, "~> 1.0"}
```

Make sure to start it at the top of your `test/test_helper.exs`:

```elixir
{:ok, _} = Application.ensure_all_started(:hound)
```

Then add the following to your test case (or case template):

```elixir
use Hound.Helpers

setup tags do
  pid = Ecto.Adapters.SQL.Sandbox.start_owner!(YourApp.Repo, shared: not tags[:async])
  on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(YourApp.Repo, pid)
  Hound.start_session(metadata: metadata)
  :ok
end
```

Hound supports multiple drivers like Chrome, Firefox, etc but it does not support concurrent tests under PhantomJS (the default).

### Wallaby

To write concurrent acceptance tests with Wallaby, first add it as a dependency to your `mix.exs`:

```elixir
{:wallaby, "~> 0.25", only: :test}
```

Wallaby can take care of setting up the Ecto Sandbox for you if you use `use Wallaby.Feature` in your test module.

```elixir
defmodule MyAppWeb.PageFeature do
  use ExUnit.Case, async: true
  use Wallaby.Feature

  feature "shows some text", %{session: session} do
    session
    |> visit("/home")
    |> assert_text("Hello world!")
  end
end
```

If you don't `use Wallaby.Feature`, you can add the following to your test case (or case template):

```elixir
use Wallaby.DSL

setup tags do
  pid = Ecto.Adapters.SQL.Sandbox.start_owner!(YourApp.Repo, shared: not tags[:async])
  on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(YourApp.Repo, pid)
  {:ok, session} = Wallaby.start_session(metadata: metadata)
end
```

Wallaby currently supports ChromeDriver and Selenium, allowing testing in almost any browser.

## Configuration

The `Plug.Exception` implementations for Ecto exceptions may be disabled by including the error in the mix configuration.

```elixir
config :phoenix_ecto,
  exclude_ecto_exceptions_from_plug: [Ecto.NoResultsError]
```

## Copyright and License

Copyright (c) 2015, Chris McCord.

Phoenix/Ecto source code is licensed under the [MIT License](https://github.com/phoenixframework/phoenix_ecto/blob/master/LICENSE).
