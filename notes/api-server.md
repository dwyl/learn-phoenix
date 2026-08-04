# API with Phoenix

## What

A step by step guide on how to create a simple JSON API with Phoenix.
The built API will provide url endpoints for retreiving quotes.

## How

### Initialise the Phoenix application

The project is created with the `mix phx.new` command.
The application only needs to return json responses.
So webpack (used for managing css image and js assets)
and html views and templates are not required.

Adding the `--no-webpack` and `--no-html` flags to the command
will remove all the unecessay code (to see all the options available run `mix phx.new`).
For example lets' create the `quote` application:

```sh
mix phx.new quote --no-webpack --no-html
```

### Create endpoint

Now that the structure of the API server has been created
we need to create a route, controller and view
which will retreive the quotes.

We could use a generator command to create automatically
these files, e.g. `mix phx.gen.json 
However because we are creating only one endpoint for now
we can create these files manually:

Let's first update `lib/quote_web/route.ex` file to define a new endpoint:

```elixir
defmodule QuoteWeb.Router do
  use QuoteWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", QuoteWeb do
    pipe_through :api
    get "/quotes", QuoteController, :index # define new endpoint
  end
end
```

This create the GET `/api/quotes` endpoint.
Notice the pipeline `:api` which will check the http requests send
by the client contain the 
[http header `Accept: application/json`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Accept)

Then we can create the `QuoteController` at `lib/quote_web/controllers/quote_controller.ex`:

```elixir
defmodule QuoteWeb.QuoteController do
  use QuoteWeb, :controller

  def index(conn, _params) do
    # see https://github.com/dwyl/quotes
    quotes = [
      %{
        author: "Thomas Edison",
        text: "If we did the things we are capable of, we would astound ourselves."
      },
      %{
        author: "Thomas Edison",
        text:
          "Opportunity is missed by most because it is dressed in overalls and looks like work."
      }
    ]

    render(conn, "index.json", quotes: quotes)
  end
end
```

We have kept the `index` action simple for now and hardcoded the list of quotes.
The render function is called with the "index.json" view and the list of quotes.

Let's create the `index.json` view at `lib/quote_web/views/quote_view.ex`:

```elixir
defmodule QuoteWeb.QuoteView do
  use QuoteWeb, :view

  def render("index.json", %{quotes: quotes}) do
    quotes
  end
end
```

The view is also kept simple and is just returning directly the list of quotes.

We can now try our API, run the server with `mix phx.server` and
access the url http://localhost:4000/api/quotes,
for example run the following curl command:

```sh
curl http://localhost:4000/api/quotes
```

You should be able to see the list of quotes.

A recap of the request/response flow:

- The client send a http request with the headers containing `Accept: application/json`
- The API server receives the request and verify the request headers with the :api pipeline
- The API call the controller then the view associated to the `/api/quotes`  GET endpoint
and returns the http response with `Content-type: application/json` in the header
- The client receive the response and knows from the headers that the body type of data is json



### Manage Cross Origin Resource Sharing

By default only the requests from the same domain name as the server are allowed.
To allow any domain names to send requests to the API,
we need to let the server allow these requests.

We can use the [cors_plug](https://hex.pm/packages/cors_plug) package to
manage CORS:

- Add the dependency `{:cors_plug, "~> 2.0"}` to `mix.exs` file and run `mix deps.get`
- Add in `endpoint.ex` file `plug CORSPlug, origin: ["*"]`

see https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS