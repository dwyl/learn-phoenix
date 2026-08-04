# Esbuild

[![CI](https://github.com/phoenixframework/esbuild/actions/workflows/main.yml/badge.svg)](https://github.com/phoenixframework/esbuild/actions/workflows/main.yml)

Mix tasks for installing and invoking [esbuild](https://esbuild.github.io/).

## Installation

If you are going to build assets in production, then you add
`esbuild` as dependency on all environments but only start it
in dev:

```elixir
def deps do
  [
    {:esbuild, "~> 0.10", runtime: Mix.env() == :dev}
  ]
end
```

However, if your assets are precompiled during development,
then it only needs to be a dev dependency:

```elixir
def deps do
  [
    {:esbuild, "~> 0.10", only: :dev}
  ]
end
```

Once installed, change your `config/config.exs` and [pick a version
for the esbuild CLI](https://github.com/evanw/esbuild/releases) of your choice:

```elixir
config :esbuild, version: "0.25.5"
```

Now you can install esbuild by running:

```bash
$ mix esbuild.install
```

And invoke esbuild with:

```bash
$ mix esbuild default assets/js/app.js --bundle --minify --target=es2016 --outdir=priv/static/assets/
```

The executable is kept at `_build/esbuild-TARGET`.
Where `TARGET` is your system target architecture.

## Profiles

The first argument to `esbuild` is the execution profile.
You can define multiple execution profiles with the current
directory, the OS environment, and default arguments to the
`esbuild` task:

```elixir
config :esbuild,
  version: "0.25.5",
  default: [
    args: ~w(js/app.js),
    cd: Path.expand("../assets", __DIR__)
  ]
```

When `mix esbuild default` is invoked, the task arguments will be appended
to the ones configured above. Note profiles must be configured in your
`config/config.exs`, as `esbuild` runs without starting your application
(and therefore it won't pick settings in `config/runtime.exs`).

## Adding to Phoenix

To add `esbuild` to an application using Phoenix, you need only four steps.  Installation requires that Phoenix watchers can accept module-function-args tuples which is not built into Phoenix 1.5.9.

First add it as a dependency in your `mix.exs`:

```elixir
def deps do
  [
    {:phoenix, github: "phoenixframework/phoenix", branch: "v1.5", override: true},
    {:esbuild, "~> 0.10", runtime: Mix.env() == :dev}
  ]
end
```

Now let's change `config/config.exs` to configure `esbuild` to use
`assets/js/app.js` as an entry point and write to `priv/static/assets`:

```elixir
config :esbuild,
  version: "0.25.5",
  default: [
    args: ~w(js/app.js --bundle --target=es2016 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]
```

> Make sure the "assets" directory from priv/static is listed in the
> :only option for Plug.Static in your lib/my_app_web/endpoint.ex

For development, we want to enable watch mode. So find the `watchers`
configuration in your `config/dev.exs` and add:

```elixir
  esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]}
```

Note we are inlining source maps and enabling the file system watcher.

Finally, back in your `mix.exs`, make sure you have a `assets.deploy`
alias for deployments, which will also use the `--minify` option:

```elixir
"assets.deploy": ["esbuild default --minify", "phx.digest"]
```

## Third-party JS packages

If you have JavaScript dependencies, you have two options
to add them to your application:

  1. Vendor those dependencies inside your project and
     import them in your "assets/js/app.js" using a relative
     path:

         import topbar from "../vendor/topbar"

  2. Call `npm install topbar --save` inside your assets
     directory and `esbuild` will be able to automatically
     pick them up:

         import topbar from "topbar"

## CSS

`esbuild` has basic support for CSS. If you import a css file at the
top of your main `.js` file, `esbuild` will also bundle it, and write
it to the same directory as your `app.js`:

```js
import "../css/app.css"
```

However, if you want to use a CSS framework, you will need to use a separate tool.
Here are some options to do so:

  * Use [standalone Tailwind](https://github.com/phoenixframework/tailwind) or
    [standalone SASS](https://github.com/CargoSense/dart_sass). Both similar to
    `esbuild`.

  * You can use `esbuild` plugins (requires `npm`). See [Phoenix' official
    guide on using them](https://hexdocs.pm/phoenix/asset_management.html).

## License

Copyright (c) 2021 Wojtek Mach, José Valim.

esbuild source code is licensed under the [MIT License](LICENSE.md).
