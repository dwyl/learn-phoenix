# Deploy Elixir umbrella app to Azure
## using Distillery and Edeliver

## Why?
Because you want to have an umbrella app in production

## What
Umbrella app containing one phoenix application, and one (or however many you
want)
supporting libraries deployed to Azure from scratch.

The goal of this README will not be to teach or explain how to make an umbrella,
phoenix or elixir applications. If you have reached the stage of wanting to
deploy an umbrella application to production (I will be making assumptions here
just to be clear) then I assume that you know how to make those applications.

If you want to learn any of the above, please see the following links

- link to elixir app
- [link to phoenix app](https://github.com/dwyl/learn-phoenix-framework/blob/master/simple-server.md)
- link to umbrella app

What we will be focusing on is taking an existing Elixir umbrella application,
which contains one supporting elixir library and a Phoenix application which
will list the Elixir app as a dependency.

## How

### Pre-requisites
+ [ ] **Elixir** installed on your localhost
+ [ ] **Phoenix** installed on your localhost
+ [ ] **Basic Knowledge** of your chosen deployment environment. e.g:
  + Amazon Web Services (**AWS**):
  [github.com/dwyl/learn-**amazon-web-services**](https://github.com/dwyl/learn-amazon-web-services)
  + Microsoft **Azure**: [github.com/dwyl/learn-microsoft-azure](https://github.com/dwyl/learn-microsoft-**azure**)
  + **Digital Ocean**: [github.com/dwyl/**DigitalOcean**-Setup](https://github.com/dwyl/DigitalOcean-Setup)
  _we will be using azure_

### Fork umbrella application

A basic Elixir umbrella app can be [found here](https://github.com/RobStallion/example_umbrella_deployment)
Fork the repo and then clone it to your local machine.

### When you have the repo locally

Make sure that it can be started and runs as expected. See the readme that is in
the [repo](https://github.com/RobStallion/example_umbrella_deployment)

You should be able to see the word "world" logged on the screen. This is not
just written the template, it is actually data that comes from the
`elixir_library`. In the page controller we are calling a function from the
elixir_library app which returns the word "world". Then we pass that word to the
front end.

This is a very simple example but it shows how an umbrella application works.

If this is working as expected then the next step is to

### Prepping for deployment
(I know right, there already 👊)

With an umbrella app, the deployment process will be a little different than
when you deploy just a phoenix application. (An example of deploying a phoenix
app to Azure can be found
[here](https://github.com/dwyl/learn-phoenix-framework/blob/master/production-deployment.md))

The first step is to add the following dependencies to your `mix.exs` file in
the root of your project
```
defp deps do
  [{:distillery, "~> 0.9"},
  {:edeliver, "~> 1.4.0"}]
end
```

After you have added these you will need to run `mix deps.get` in the command
line. This will add them as dependencies to your project

Next, add the following line to your `.gitignore` file...
```
.deliver/releases/
```
That will ensure that the binary releases aren't added to GitHub.
(no point adding megabytes of binary to GitHub!)

Next we need to go into the `apps/phoenix_app` folder and move the
`package.json` and `brunch-config.js` files to the root of the elixir project.

Once you have moved them, open the `package.json` and update the file paths in
the dependencies to the following...

```
"dependencies": {
  "phoenix": "file:deps/phoenix",
  "phoenix_html": "file:deps/phoenix_html"
}
```

The reason this needs to be done is so that the node modules can be installed
from the root of the project. This is needed for when you deploy.

Next open the `brunch-config.js`. This file will need to be edited in a few more
places than the previous one but is still fairly straight forward.

Everywhere you see `web/static` it needs to be prepended with `apps/phoenix_app`.
It should look like
[this](https://github.com/katbow/umbrella_deployment/blob/master/brunch-config.js)
when you are finished with it.

What this will do is allow your umbrella app to compile your `phoenix_app`
application's static assets into the `apps/phoenix_app_dev/priv/static/`. This
is where phoenix applications read all static files from so is a vital step.

Next step is to make sure that your `apps/phoenix_app/config/prod.exs` has a
config set up for the Repo you are using. To do this all we have to do is copy
the following lines from `apps/phoenix_app/config/dev.exs`...

```
config :phoenix_app, PhoenixApp.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "phoenix_app_dev",
  hostname: "localhost",
  pool_size: 10
```

This will allow your production environment to be able to read from the database.
(although we are not actually using the database in this walkthrough, we thought
it best to provide an example config as most real applications will be connected to a
database)
