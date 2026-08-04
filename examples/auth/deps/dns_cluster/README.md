# DNSCluster

Simple DNS clustering for distributed Elixir nodes.

## Installation

The package can be installed by adding `dns_cluster` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dns_cluster, "~> 0.1.1"}
  ]
end
```

Next, you can configure and start the cluster by adding it to your supervision
tree in your `application.ex`:

```elixir
children = [
  {Phoenix.PubSub, ...},
  {DNSCluster, query: Application.get_env(:my_app, :dns_cluster_query) || :ignore},
  MyAppWeb.Endpoint
]
```

If you are deploying with Elixir releases, the release must be set to support longnames and
the node must be named. These can be set in your `rel/env.sh.eex` file:

```sh
#!/bin/sh
export RELEASE_DISTRIBUTION=name
export RELEASE_NODE="myapp@fully-qualified-host-or-ip"
```

By default, nodes from the same release will have the same cookie. If you want different
applications or releases to connect to each other, then you must set the `RELEASE_COOKIE`,
either in your deployment platform or inside `rel/env.sh.eex`:

```sh
#!/bin/sh
...
export RELEASE_COOKIE="my-app-cookie"
```
