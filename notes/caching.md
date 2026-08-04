# Caching in Phoenix applications

## Why?

Despite the
[speed of Phoenix applications](https://github.com/dwyl/learn-phoenix-framework#why),
database queries are a bottleneck which can slow down your app. Oftentimes you
may be loading the same or similar data anytime someone accesses a page. Caching
previously loaded data can help speed up your app and avoid the query bottleneck!

## What

There are a
[number of libraries available](https://github.com/h4cc/awesome-elixir#caching)
for caching data with Phoenix. We are going to be looking at
[con_cache](https://github.com/sasa1977/con_cache)
specifically, which is an ETS based key/value storage.

## How

### Setup ConCache

* Add `:con_cache` to your deps

```elixir
defp deps do
  [{:con_cache, "~> 0.12.0"}, ...]
end
```

* Add it to your application

```elixir
def application do
  [applications: [:con_cache, ...]]
end
```

* Run `mix deps.get`
* Start the cache from a supervisor in `lib/<my_app>.ex`. You can add to the
list of children as below.

```elixir
    children = [
      supervisor(MyApp.Repo, []),
      supervisor(MyApp.Endpoint, []),
      # add ConCache here. :my_cache can be whatever you want to name your cache
      supervisor(ConCache, [[], [name: :my_cache]]),
      worker(Segment, [Application.get_env(:segment, :write_key)])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Healthlocker.Supervisor]
    Supervisor.start_link(children, opts)
  end
```
* You're ready to start caching!

### Using ConCache

There are a number of [functions](https://hexdocs.pm/con_cache/ConCache.html#functions)
you can use depending on how you would like to store your data. Below are some
basics, but the full extent is covered in the
[docs](https://hexdocs.pm/con_cache/ConCache.html).

![using-conn-cache](https://user-images.githubusercontent.com/1287388/27686386-7290dcce-5cca-11e7-8654-be404250a204.png)

[`ConnCache.get_or_store(cache_id, key, store_fun)`](https://hexdocs.pm/con_cache/ConCache.html#get_or_store/3)
is a particularly useful function which acts as a get from the cache if the
item is already there, or stores the item if it is not.

### Testing with ConnCache

Because ConnCache introduces state to your system, some tests may compromise
the execution of other tests.

There are ways around this, as listed by the creator of ConnCache
[here](https://github.com/sasa1977/con_cache#testing-in-your-application).
