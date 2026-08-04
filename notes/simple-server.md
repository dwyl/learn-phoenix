# Setting up a simple Phoenix Application

## Intro

`Phoenix` makes getting an simple application up and running a **breeze** 💨 and this `README` is going to show you how it's done. Without further ado let's get started

You will need to have `node`, `Hex`, `PostgreSQL`, `Elixir` and `Erlang` installed for this. If you do not have them at the moment then just go to the links provided or follow the instructions.

##### Links

+ [`Erlang` and `Elixir`](http://elixir-lang.org/install.html)
+ [`PostgreSQL`](https://wiki.postgresql.org/wiki/Detailed_installation_guides)
+ [`node`](https://nodejs.org/en/download/)

##### Instructions

+ Install `Hex` - `mix local.hex`

## First step - Installing Phoenix

The first step, as you might have guessed, is to actually install
`Phoenix` and that can be done with the command below.

`mix archive.install https://github.com/phoenixframework/archives/raw/master/phoenix_new.ez`

That's it!!

## Middle bit - Creating your Application

Now that we're done with all the installing time to actually get down to creating your phoenix app.
Phoenix also makes this straight forward. It can be done with a few commands.

Start by running `mix phoenix.new` from any directory to bootstrap your phoenix application. Phoenix will accept either an absolute or relative path for the directory of your new project. So for example, if the name of your project is hello_phoenix then either of these will work

`mix phoenix.new /Users/me/work/elixir-stuff/hello_phoenix`

`mix phoenix.new hello_phoenix`

When you run the `mix phoenix.new` Phoenix will create all the files and folders needed for the application. Once that is done it will as you if you want to install dependencies.

`Fetch and install dependencies? [Yn]`

Say yes to this and all the dependencies needed will be installed. When it is finished you will be prompted to `cd` into your newly created directory where you will then be able to create your database. Again this is just one simple command. You will need to have Postgres running for this to work.

`mix ecto.create`

(If you get errors this might help: [#53](https://github.com/dwyl/learn-phoenix-framework/issues/53)).

And that is that. If all has gone well you have just created your phoenix application.

## Final hurdle (already) - Exploring your Shiny New Application

Now it's time to have a look at all your new files and folders and to actually see your application run 👍.

First things first, you will want to start your server with

`mix phoenix.server`

(If you get errors this might help: [#53](https://github.com/dwyl/learn-phoenix-framework/issues/53)).

By default Phoenix accepts requests on port 4000 so you will get a message in your terminal that looks something like this...

`Running HelloPhoenix.Endpoint with Cowboy using http://localhost:4000`

Now all that's left is to go to the endpoint in your browser and look at your Phoenix Application which should be displaying the Phoenix Framework welcome page.

## Summary (TLDR)

All commands from start to finish

+ `mix local.hex`
+ `mix archive.install https://github.com/phoenixframework/archives/raw/master/phoenix_new.ez`
+ `mix phoenix.new hello_phoenix`
+ Type `y` when prompted to install dependencies
+ `cd hello_phoenix`
+ `mix ecto.create` (If you get errors this might help: [#53](https://github.com/dwyl/learn-phoenix-framework/issues/53))
+ `mix phoenix.server`(If you get errors this might help: [#53](https://github.com/dwyl/learn-phoenix-framework/issues/53))

## Learn more

+ [Official website](http://www.phoenixframework.org/)
+ [Guides](http://www.phoenixframework.org/docs/overview)
+ [Docs](https://hexdocs.pm/phoenix/Phoenix.html)
+ [Mailing list](http://groups.google.com/group/phoenix-talk)
+ [Source](https://github.com/phoenixframework/phoenix)
