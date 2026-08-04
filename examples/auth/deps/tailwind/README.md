# Tailwind

[![CI](https://github.com/phoenixframework/tailwind/actions/workflows/main.yml/badge.svg)](https://github.com/phoenixframework/tailwind/actions/workflows/main.yml)

Mix tasks for installing and invoking [tailwindcss](https://tailwindcss.com) via the
stand-alone [tailwindcss cli](https://github.com/tailwindlabs/tailwindcss/tree/main/packages/%40tailwindcss-standalone)

## Installation

If you are going to build assets in production, then you add
`tailwind` as dependency on all environments but only start it
in dev:

```elixir
def deps do
  [
    {:tailwind, "~> 0.3", runtime: Mix.env() == :dev}
  ]
end
```

Once installed, change your `config/config.exs` to pick your
Tailwind version of choice:

```elixir
config :tailwind, version: "4.1.12"
```

Note that `:tailwind` 0.3+ assumes Tailwind v4+ by default.
It still supports Tailwind v3, but some configuration options
when setting up a new project might be different. If you use
Tailwind v3, also have a look at [the README in the 0.2 branch](https://github.com/phoenixframework/tailwind/blob/v0.2/README.md).

Now you can install Tailwind by running:

```bash
$ mix tailwind.install
```

or if your platform isn't officially supported by Tailwind,
you can supply a third party path to the binary the installer wants
(beware that we cannot guarantee the compatibility of any third party executable):

```bash
$ mix tailwind.install https://people.freebsd.org/~dch/pub/tailwind/v3.2.6/tailwindcss-freebsd-x64
```

And invoke Tailwind with:

```bash
$ mix tailwind default
```

The executable is kept at `_build/tailwind-TARGET`.
Where `TARGET` is your system target architecture.

## Profiles

The first argument to `tailwind` is the execution profile.
You can define multiple execution profiles with the current
directory, the OS environment, and default arguments to the
`tailwind` task in your `config/config.exs`:

```elixir
config :tailwind,
  version: "4.1.12",
  default: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]
```

When `mix tailwind default` is invoked, the task arguments will be appended
to the ones configured above.

## Adding to Phoenix

Note that applications generated with Phoenix older than 1.8 still use Tailwind v3 by default.
If you're using Tailwind v3 please refer to [the README in the v0.2 branch](https://github.com/phoenixframework/tailwind/blob/v0.2/README.md#adding-to-phoenix)
instead.

To add Tailwind v4 to an application using Phoenix, first add this package
as a dependency in your `mix.exs`:

```elixir
def deps do
  [
    {:phoenix, "~> 1.8"},
    {:tailwind, "~> 0.3", runtime: Mix.env() == :dev}
  ]
end
```

Also, in `mix.exs`, add `tailwind` to the `assets.deploy`
alias for deployments (with the `--minify` option):

```elixir
"assets.deploy": ["tailwind default --minify", ..., "phx.digest"]
```

Now let's change `config/config.exs` to tell `tailwind`
to build our css bundle into `priv/static/assets/css`.
We'll also give it our `assets/css/app.css` as our css entry point:

```elixir
config :tailwind,
  version: "4.1.12",
  default: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]
```

> Make sure the "assets" directory from priv/static is listed in the
> `:only` option for Plug.Static in your `lib/my_app_web/endpoint.ex`

If your Phoenix application is using an umbrella structure, you should specify
the web application's asset directory in the configuration:

```elixir
config :tailwind,
  version: "4.1.12",
  default: [
    args: ...,
    cd: Path.expand("../apps/<folder_ending_with_web>", __DIR__)
  ]
```

For development, we want to enable watch mode. So find the `watchers`
configuration in your `config/dev.exs` and add:

```elixir
  tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
```

Note we are enabling the file system watcher.

Finally, create the relevant `assets/css/app.css` file:

```css
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/YOUR_APP_web";

@custom-variant phx-click-loading (.phx-click-loading&, .phx-click-loading &);
@custom-variant phx-submit-loading (.phx-submit-loading&, .phx-submit-loading &);
@custom-variant phx-change-loading (.phx-change-loading&, .phx-change-loading &);
```

We also strongly recommend setting up the `@source` paths in your in `app.css`
file to watch `assets/css`, `assets/js` and `lib/YOUR_APP_web`, as above.
Without those, too many files (including build artifacts) may be watched,
leading to frequent recompilations.

## Updating from Tailwind v3 to v4

For a typical Phoenix application, updating from Tailwind v3 to v4 requires the following steps:

1.  Update the `:tailwind` library to version 0.3+

    ```diff
     defp deps do
       [
    -    {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
    +    {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
       ]
     end
    ```

2.  Adjust the configuration to run Tailwind from the root of your repo (or the web app in an umbrella project):

    ```diff
     config :tailwind,
    -   version: "3.4.13",
    +   version: "4.1.12",
        default: [
          args: ~w(
    -       --config=tailwind.config.js
    -       --input=css/app.css
    -       --output=../priv/static/assets/app.css
    +       --input=assets/css/app.css
    +       --output=priv/static/assets/css/app.css
         ),
    -    cd: Path.expand("../assets", __DIR__)
    +    cd: Path.expand("..", __DIR__)
      ]
    ```

    This allows Tailwind to automatically pick up classes from your project. Tailwind v4 does not require explicit configuration of sources.

3.  Adjust the Tailwind imports in your app.css

    ```diff
    -@import "tailwindcss/base";
    -@import "tailwindcss/components";
    -@import "tailwindcss/utilities";
    +@import "tailwindcss";
    ```

4.  Follow the [Tailwind v4 upgrade guide](https://tailwindcss.com/docs/upgrade-guide) to address deprecations.

5.  Optional: remove the `tailwind.config.js` and switch to the new CSS based configuration. For more information, see the previously mentioned upgrade guide and the [documentation on functions and directives](https://tailwindcss.com/docs/functions-and-directives).

## License

Copyright (c) 2022 Chris McCord.
Copyright (c) 2021 Wojtek Mach, José Valim.

tailwind source code is licensed under the [MIT License](LICENSE.md).
