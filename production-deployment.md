# _Production_ Phoenix Deployment

## _using_ Distillery and Edeliver

**Note**: these notes are **_super_ detailed**
for **Zero-downtime Deployment**
i.e. this will create a **100% Uptime System**.
Some of the steps may be out-of-date.
Please proceed with caution.
If you're following them
and have time to update,
**please submit a PR**.

## Why?

The Erlang VM ("BEAM") gives us "**_Hot-code Upgrades_**"
which means we can do "**_Zero Downtime Deployment_**". <br />
So **people** can **_continue using_** the **app**
`while` the app is **being updated/upgraded**!
Most other languages/frameworks/platforms make you work _really_ hard
to get this feature, so _not_ using it seems kinda wasteful!

> _**Note**: If you **don't need** "**Hot-code Upgrades**" and just want
a way of deploying your Phoenix app to your own infrastructure,
see:_
[https://github.com/dwyl/**learn-devops**](https://github.com/dwyl/learn-devops/blob/master/nodejs-digital-ocean-centos-dokku.md)

## What?

Production Phoenix Web Application Deployment
in **_Under_ 60 Minutes _from scratch_**
(_or your money back!!_)

### Tools?

The two (_main_) tools we will be using are:

+ **Distillery**: https://github.com/bitwalker/distillery - builds the release
binary including BEAM so there is _nothing_ to install on the VM!
+ **edeliver**: https://github.com/boldpoker/edeliver - deploys the release
to VM(s) using SSH.

> **Note**: We will also be using `SSH` ("_Secure Shell_")
to login to remote instances. <br />
If you are _unfamiliar_ with SSH, please see: <br />
https://www.digitalocean.com/community/tutorials/ssh-essentials-working-with-ssh-servers-clients-and-keys

## _Who_?

This guide is intended for people who
are **_completely new_** to **Phoenix**. <br />
While it _can_ be used by "_developers_" it's
_actually_ meant for people who identify as "**_Dev Ops_**"
or "**IT Operations**". <br />
_Therefore_ **_No Assumptions_** are made about coding skills or Elixir/Phoenix knowledge.

> _If **anything** is **unclear** or you have a **any questions**, <br />
please **open** an **issue**: https://github.com/dwyl/learn-devops/issues
(thanks)_!

## How?

This **_step-by-step guide_** is comprised
of the following **_four_ sections**:

1. **Single Server** Setup - when you only want to **pay** for a single server
  but want to get a lot more for your money than on Heroku.
2. **Single Server _with Continuous Integration_** Setup -
similar to section 1. (_above_) but with Travis-CI doing the deployment for you!
3. **_PostgreSQL_** Setup
4. "**_High Availability Cluster_**" setup that can (easily) handle
[_**Millions of Concurrent Connections**_](http://www.phoenixframework.org/blog/the-road-to-2-million-websocket-connections)
with **_Zero_ Downtime** Delpoys/Updates!

### 1. Single Server "Direct" Deployment

For the purposes of this guide I will be using Microsoft Azure
Linux Virtual Machines, <br />
but this setup has _also_ been tested on:
+ Amazon Web Services (AWS) Elastic Cloud Compute (EC2)
+ Digital Ocean

> If you prefer to use a different hosting/"Cloud" service, <br />
please let us know: https://github.com/dwyl/learn-devops/issues

### Deploy a "_Hello World_" Phoenix App using `Edeliver`

Our objective is to _**keep things** as **simple** as **possible**_,
so we are _not_ going to deploy an _existing_ app;
Instead we are deploying a "**Hello World**" **app** in order to
test _just_ the deployment process ("_pipeline_") in _isolation_
(_minimising the variables to avoid contending with any "application issues"_).

> The _complete_ code for this example is available at:
https://github.com/nelsonic/hello_world_edeliver

### 1.1 Pre-Requisites (_Before You Start_)

+ [ ] **Elixir** _installed_ on your localhost
+ [ ] **Phoenix** _installed_ on your localhost
+ [ ] **_Basic_ Knowledge** of your chosen deployment environment. e.g:
  + Amazon Web Services (**AWS**):
  [github.com/dwyl/learn-**amazon-web-services**](https://github.com/dwyl/learn-amazon-web-services)
  + Microsoft **Azure**: [github.com/dwyl/learn-microsoft-azure](https://github.com/dwyl/learn-microsoft-**azure**)
  + **Digital Ocean**: [github.com/dwyl/**DigitalOcean**-Setup](https://github.com/dwyl/DigitalOcean-Setup)
+ [ ] **~~25~~ 45 Minutes** of distraction-free time.

### 1.2 Create the `hello_world_edeliver` Phoenix Project on Your Localhost

Create a _new_ Phoenix web application project with the following command:

```sh
mix phoenix.new hello_world_edeliver --no-ecto
```

> **Note**: The _reason_ for `--no-ecto` is
so we don't have to setup a Database _yet_.
We'll cover PostgreSQL setup in "**Part 3**".

#### 1.2.2 Install (Default) Dependencies

You will be prompted to install "_Fetch and install dependencies? [Yn]_"
![deploy-fetch-and-install](https://cloud.githubusercontent.com/assets/194400/26062707/896dd5ce-3983-11e7-9f33-67a94c323b60.png)

Type "**Y**" then press [**Enter**] to fetch the required dependencies.

![dependencies-installed](https://cloud.githubusercontent.com/assets/194400/26062763/b57efa1c-3983-11e7-8cba-9e0c397e72d5.png)

#### 1.2.3 Run the `hello_world_edeliver` Phoenix Project _Locally_

Next, change directory into the project and _run_ the server:

```sh
cd hello_world_edeliver
mix phoenix.server
```

You should see the following in your terminal window:
![app-running](https://cloud.githubusercontent.com/assets/194400/26062982/7efae43c-3984-11e7-882b-ae38e207edaf.png)

#### 1.2.4 Visit in Web Browser

Now, visit the project in your web browser (_to confirm it's working_): <br />
http://localhost:4000/

![phoneix-project-working](https://cloud.githubusercontent.com/assets/194400/26063083/cf8376b2-3984-11e7-8af7-8421ec020fad.png)

### 1.3 Install Edeliver & Distillery Dependencies

Let's add the two necessary dependencies we need to package and deploy our app:

#### 1.3.1 Open/Edit Your `mix.exs` File

Open/edit the `mix.exs` file then add `:edeliver` & `:distillery`
to the list of dependencies (_usually at the bottom of the file_):

![phoenix-add-edeliver-dependencies](https://cloud.githubusercontent.com/assets/194400/26064396/b81706c0-3988-11e7-9972-405020b7741f.gif)

```elixir
{:edeliver, "~> 1.4.0"},
{:distillery, ">= 0.8.0", warn_missing: false}
```

#### 1.3.2 Include `:edeliver` in `applications` List

Find the section in `mix.exs` that starts with:
```elixir
def application do
    [mod: {HelloWorldEdeliver, []},
      applications: [ :phoenix
```

Add `:edeliver` to the end of the list:

![phoenix-add-edeliver-to-apps](https://cloud.githubusercontent.com/assets/194400/26064822/fdad7920-3989-11e7-8e2d-e4a0d759ea7c.gif)

> _**Note**: we like to have **one** app per line for clarity._

#### 1.3.3 Install

In your terminal run the command:

```sh
mix deps.get
```

If the dependency installation _would_, you should see:

![deploy-install-deps](https://cloud.githubusercontent.com/assets/194400/26066672/97b38f14-398f-11e7-8f1e-7a8d592202c3.png)

### 1.4 Update `config/prod.exs` Settings

Open/Edit the `config/prod.exs` file and edit the following:

#### 1.4.1 Update the `config` Section

Locate the `config` line <br />
and update the settings for `url`, `server`, `root` and `version`:

![update-prod-exs](https://cloud.githubusercontent.com/assets/194400/26068996/67baca40-3997-11e7-8ad7-bbd6684c7079.gif) <br />
End result:

```elixir
config :hello_world_edeliver, HelloWorldEdeliver.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [host: "...", port: {:system, "PORT"}],
  server: true,
  root: ".",
  version: Mix.Project.config[:version],
  cache_static_manifest: "priv/static/manifest.json"
```

#### 1.4.2 No Secrets > Comment Out The Line (_For Now_)

Open/Edit the `config/prod.exs` file, scroll to the bottom <br />
and comment out the line that reads: <br />

```elixir
import_config "prod.secrets.exs"
```

![phoenix-comment-out-prod-secrets](https://cloud.githubusercontent.com/assets/194400/26068080/2e78078c-3994-11e7-97b5-918ee7142565.gif)

### 1.5 Configure Edeliver Deployment Settings

#### 1.5.1 Run the `mix release.init` command/task

In the terminal on your localhost, run the following command:

```sh
mix release.init
```

You should see the following output (_or similar_):

![mix-release](https://cloud.githubusercontent.com/assets/194400/26070132/605ce8ec-399b-11e7-916f-395c3e5a67d9.png)

That will have create a `/rel` directory in the project.
with `config.exs` file in it:

![image](https://cloud.githubusercontent.com/assets/194400/26070192/9cfb41cc-399b-11e7-83b3-d193b4273bab.png)

> For an _example_ of the the complete  `rel/config.exs` file see: <br />
https://github.com/nelsonic/hello_world_edeliver/blob/master/rel/config.exs

#### 1.5.2 Create a `.deliver` _Directory_

Create a `.deliver` directory in the project:

```sh
mkdir .deliver
```

#### 1.5.3 Create the `.deliver/config` _File_

Create/edit the `.deliver/config` file in your choice of editor e.g:

```sh
vi .deliver/config
```
> Yes, the `.deliver/config` file does not have a file extension. <br />
Don't worry, it's _meant_ to be that way.

Paste the following into the file:

```bash
APP="hello_world_edeliver"

BUILD_HOST="52.232.127.28"
BUILD_USER="azure"
BUILD_AT="/home/azure/hello_world_edeliver/builds"

PRODUCTION_HOSTS="52.232.127.28"
PRODUCTION_USER="azure"
DELIVER_TO="/home/azure"

pre_erlang_clean_compile() {
  status "Installing NPM dependencies"
  __sync_remote "
    [ -f ~/.profile ] && source ~/.profile
    set -e

    cd '$BUILD_AT'
    npm install $SILENCE
  "

  status "Building static files"
  __sync_remote "-wi
    [ -f ~/.profile ] && source ~/.profile
    set -e

    cd '$BUILD_AT'
    mkdir -p priv/static
    npm run deploy $SILENCE
  "

  status "Running phoenix.digest"
  __sync_remote "
    [ -f ~/.profile ] && source ~/.profile
    set -e

    cd '$BUILD_AT'
    APP='$APP' MIX_ENV='$TARGET_MIX_ENV' $MIX_CMD phoenix.digest $SILENCE
  "
}
```

##### `.deliver/config` _File_ Settings Explained

The _important_ bits in the `.deliver/config` file are:

+ `APP="hello_world_edeliver"` - the name of your app.
+ `BUILD_HOST="52.232.127.28"` - IP address of the server the _binary_
of your Phoenix App is going to be built on. For now
(_in the single server setup_) this is _the same_ as the "Production" IP.
+ `BUILD_USER="azure"` - username used to login to the VM, in this case
the Azure VM we setup according to the instructions in: <br />
https://github.com/dwyl/learn-microsoft-azure#2-create-a-virtual-machine
+ `BUILD_AT="/home/azure/hello_world_edeliver/builds"` - the location on the
"Build" VM where your build will be stored.
+ `PRODUCTION_HOSTS="52.232.127.28"` - same IP address as Build (_for now_).
+ `PRODUCTION_USER="azure"` - same as build server (_for now_)
+ `DELIVER_TO="/home/azure"` - location on the Production server where
the _compiled_ version of the App will deployed to.

> The `pre_erlang_clean_compile()` function in `.deliver/config`
defines the "_build steps_" to compile the static assets in the project. <br />
> The keen observer will notice that we're running `source ~/.profile`
inside the `pre_erlang_clean_compile()` function.
We will define the `~/.profile` below!
(_`~/.profile` is where we will keep environment variables on the VM_!)

#### 1.5.4 Add `.deliver/releases` to `.gitignore`

On your localhost in your terminal run the following command:

```sh
echo ".deliver/releases/" >> .gitignore
```

That will ensure that the _binary_ releases aren't added to GitHub.
(_no point adding megabytes of binary to GitHub_!)

<br />

### 1.6 Login to the (_Remote_) Virtual Machine

> The next section requires SSH access to the (_remote_) Virtual Machine (VM).
> in our case the VM's IP address is `52.232.127.28` <br />
> therefore we login to VM using `ssh azure@52.232.127.28`. <br />
> For detail see: https://github.com/dwyl/learn-microsoft-azure#9-login-with-ssh

#### 1.6.1 Install "Build Tools" on the Virtual Machine

We need to install the essential build tools on the VM in order to
build the release:

Add the Erlang Solutions release:

```sh
wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb && sudo dpkg -i erlang-solutions_1.0_all.deb
```

You should see the following output (_or similar_):
![install erlang](https://cloud.githubusercontent.com/assets/194400/26072769/b63b0e98-39a4-11e7-8cf8-7363ab28fb55.png)

Update your VM (_to install erlang and any security updates_)

```sh
sudo apt-get update
```

![update VM](https://cloud.githubusercontent.com/assets/194400/26072850/f6412f40-39a4-11e7-9130-69d7c8e3de31.png)

Now install remaining build dependencies including node.js
(_for compiling static assets_):

```sh
curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
sudo apt-get install elixir erlang-base-hipe build-essential erlang-parsetools erlang-dev nodejs -y
```

![install dependencies](https://cloud.githubusercontent.com/assets/194400/26072983/5496104c-39a5-11e7-9d56-06ecce0cbbba.png)

> Node.js installed as per the "_official_" instructions: <br />
https://nodejs.org/en/download/package-manager/#debian-and-ubuntu-based-linux-distributions

##### Confirm Elixir is Installed on the VM

Run the following command to _confirm_ Elixir is installed on the VM:

```sh
iex -s
```

You should see:
![elixir installe](https://cloud.githubusercontent.com/assets/194400/26073552/236bb2e0-39a7-11e7-979b-14f953309065.png)


<!--
#### 1.6.2

```
mix local.hex
mix archive.install https://github.com/phoenixframework/archives/raw/master/phoenix_new.ez
```
-->

#### 1.6.2 Edit Your `~/.profile` File on Azure Instance to set TCP Port for Phoenix

Your Phoenix Web Application expects to have an environment variable
defined for the TCP PORT which the app will listen on.
In our case we are going to stick with the default and use `4000`.

Run the following command to append the line
`export PORT=4000` to your `~/.profile` file:

```sh
echo "export PORT=4000" >> ~/.profile
```

Then run the following command to ensure that `~/.profile` file is _loaded_:

```sh
source ~/.profile
```

You can _confirm_ that the `PORT` environment variable is now define on the VM
by running the `printenv` command:

```sh
printenv
```

![azure-define-port](https://cloud.githubusercontent.com/assets/194400/26028291/5c29b336-3815-11e7-8ca3-3f595b12579c.png)

### Redirect TCP Port 80 to Port 4000 (where our app is listening)

On the Azure Instance run the following command:

```sh
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j REDIRECT --to-port 4000
```

To _confirm_ the routing from port 80 to 4000 run the following command:

```sh
sudo iptables -t nat --line-numbers -L
```

![azure-port-redirect-80-to-4000](https://cloud.githubusercontent.com/assets/194400/26028325/1a9ee228-3816-11e7-9dd0-d04fb09d6169.png)

Now when you _deploy_ the app to this instance
it will "_listen_" on PORT 4000,
but the Firewall will re-route `http` requests from port `80` to `4000`.

### Build the Release

Run the following command on your localhost (_**not** logged into the VM_):

```sh
mix edeliver build release --verbose
```

> Wait for the build to compile ... https://xkcd.com/303/

Provided you followed _all_ the instructions above you should expect to see:

![release-build-success](https://cloud.githubusercontent.com/assets/194400/26074008/49f18c5e-39a8-11e7-94c4-9e40f59595c6.png)

### Deploy your Phoenix Web App using EDeliver

Deploy the release to the VM by running this command on your localhost:

```sh
mix edeliver deploy release to production
```

You should see:
![deploy-success](https://cloud.githubusercontent.com/assets/194400/26075001/a82cf09e-39ab-11e7-81e2-4f66f4c8d622.png)

#### Run the App on the VM

Start the app on the VM by running this command on your localhost:

```sh
mix edeliver start production
```

You should expect to see the following output _confirming_ the app started:
![production-start-succcess](https://cloud.githubusercontent.com/assets/194400/26075108/06c3b232-39ac-11e7-89a8-cb8f3178ccad.png)

### Confirm the Phoenix App is Working in a Web Browser

Visit your app by IP Address in your Web Browser. e.g: http://52.232.127.28

![phoenix-app-working-on-azure](https://cloud.githubusercontent.com/assets/194400/26075611/c91fae3e-39ad-11e7-8672-ef898e15c130.png)

### Update the App to Re-Test Deployment

Let's update the template in `web/templates/page/index.html.eex`
so that we can test the production is working.

![update-file](https://cloud.githubusercontent.com/assets/194400/26075790/7249ad7a-39ae-11e7-9359-020a7b69a3a6.gif)

`git commit` your changes. then re-deploy:

```sh
mix edeliver build release --verbose
mix edeliver deploy release to production --verbose
mix edeliver start production
```

Output from redeploy:
![output-from-redeploy](https://cloud.githubusercontent.com/assets/194400/26076571/1659ba66-39b1-11e7-9eb0-15687d419ad1.png)

Result in browser:
![image](https://cloud.githubusercontent.com/assets/194400/26076536/fb546ebe-39b0-11e7-865b-b48639abc87b.png)

# 2. Automated Continuous Deployment (CD)

See:
+ https://github.com/dwyl/learn-travis
+ https://github.com/dwyl/learn-travis/issues/19
+ example: https://github.com/healthlocker/healthlocker/blob/master/.travis.yml

# 3. PostgreSQL

For this tutorial we will be using the **Microsoft Azure PostgreSQL _Service_**,
because they handle Scaling, Replication and Backups. <br >
See: https://github.com/dwyl/learn-microsoft-azure/issues/5

> If you are interested in knowing how to deploy your own PostgreSQL
High Availability Cluster _From scratch_, let us know! <br />
Please leave a comment on: https://github.com/dwyl/learn-postgresql/issues/38

The steps are the same as the "Single Server Setup" (_above_)
except for the following differences:
1. The app uses a database
2. use environment variables for database settings in `/config/prod.secret.exs`
3. ***commit*** `/config/prod.secret.exs` file to github
because it's using Environment Variables which
are stored in the `~/.profile` file.

sample `/config/prod.secret.exs` file:

```elixir
config :pxblog, Pxblog.Endpoint,
  secret_key_base: System.get_env("SECRETE_KEY_BASE")

# Configure your database
config :pxblog, Pxblog.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: System.get_env("DATABASE_USERNAME"),
  password: System.get_env("DATABASE_PASSWORD"),
  database: System.get_env("DATABASE_NAME"),
  hostname: System.get_env("DATABASE_HOST"),
  pool_size: 20
```

Sample `~/.profile` file:

```sh
export PORT=4000
export DATABASE_USERNAME=postgres
export DATABASE_PASSWORD={yourpassword}
export DATABASE_HOST=pxblog.postgres.database.azure.com
export DATABASE_NAME=postgres
export SECRETE_KEY_BASE={your_super_long_secret_key}
```

# 4. Cluster Setup Server

Thankfully, if you followed the "Single Server Setup" (_above_),
a lot of this will be _familiar_ to you.

The difference are
1. in your `.deliver/config` file
you will list multiple IP Addresses for the Production Nodes.
2. Update app configuration so the servers in the cluster
are aware of each other so that channels work regardless of which
server/node the client connected to.


<!-- keeping this for now ...
+ SSH to server as root e.g: `ssh root@178.62.57.75`
(_replace for your IP Address_)
+ `sudo apt-get install git`
  + `git config --global user.name "Your Name"`
  + `git config --global user.email "your@email.co.uk"`
+ `wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb && sudo dpkg -i erlang-solutions_1.0_all.deb`
+ `sudo apt-get update`
+ `sudo apt-get install elixir`
+ `mix local.hex`
+ `mix archive.install https://github.com/phoenixframework/archives/raw/master/phoenix_new.ez`
+ `sudo apt-get install erlang-base-hipe`
+ `sudo apt-get install build-essential`
+ `sudo apt-get install erlang-dev`
+ `chmod -R 777 /opt`
+ `mkdir /git`
+ `chmod -R 777 /git`

+ On the _remote_ server,
Create the file `/home/builder/prod.secret.exs` with this command:
`mkdir -p /home/builder/ && vi /home/builder/prod.secret.exs`
-->

### Setup EDeliver Project

+ add edeliver dependency in your `mix.exs` file (pointing to master branch on GH for now...):
`{:edeliver, git: "https://github.com/boldpoker/edeliver.git"}`
+ change `{:phoenix_live_reload, "~> 1.0", only: :dev}` to `{:phoenix_live_reload, "~> 1.0"}`
+ add `, :edeliver, :phoenix_live_reload` to applications list
+ `mix deps.get`
+ `mix deps.compile`
+ `mkdir .deliver && touch .deliver/config` to create the `.deliver` directory and config file.
+ populate config file with the following:

```sh
#!/usr/bin/env bash

APP="my_awesome_app" # name of your release

BUILD_HOST="server ip / hostname" # host where to build the release
BUILD_USER="root" # local user at build host
BUILD_AT="/git/my_awesome_app/builds" # build directory on build host
RELEASE_DIR="/git/my_awesome_app/builds/rel/my_awesome_app"
RELEASE_VERSION=0.0.1

STAGING_HOSTS="server ip / hostname" # staging / test hosts separated by space
STAGING_USER="git" # local user at staging hosts
TEST_AT="/test/my_awesome_app" # deploy directory on staging hosts. default is DELIVER_TO

PRODUCTION_HOSTS="server ip / hostname" # deploy / production hosts separated by space
PRODUCTION_USER="root" # local user at deploy hosts
DELIVER_TO="/opt/my_awesome_app" # deploy directory on production hosts

# For *Phoenix* projects, symlink prod.secret.exs to our tmp source
pre_erlang_get_and_update_deps() {
  local _prod_secret_path="/home/builder/prod.secret.exs"
  if [ "$TARGET_MIX_ENV" = "prod" ]; then
    __sync_remote "
      ln -sfn '$_prod_secret_path' '$BUILD_AT/config/prod.secret.exs'
    "
  fi
}
```

Paste the contents of your _local_ `config/prod.secret.exs` into the remote one.

```sh
mix release.init
MIX_ENV=prod mix release --env=prod
```

mix edeliver build release --branch=master --verbose

### X. Set Firewall Re-Routing for PORT 4000 > 80


On the server run the following command:

```sh
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j REDIRECT --to-port 4000
```

To _confirm_ the routing from port 80 to 4000 run the following command:

```sh
sudo iptables -t nat --line-numbers -L
```

That should _list_ the routing rules:
![iptables-list-rules](https://cloud.githubusercontent.com/assets/194400/26026888/21132ea8-37fc-11e7-8a48-00a0fb2f1746.png)

**Note**: If you need to _undo_ this command run:

```sh
sudo iptables -t nat -F
```

That removes any "forward" rules so port 80 will no longer forward it's traffic to port 4000.

## Credits

_**Credit**: the instructions in this "**Hello World**"
deployment are adapted from the **superb** post by @pcorey:_ <br />
http://www.east5th.co/blog/2017/01/16/simplifying-elixir-releases-with-edeliver
<br />
_We have merely **simplified**
(or in some cases **expanded/clarified**) the steps. <br />
But **all** credit goes to Pete for distilling the instructions
for using Edeliver in the first place!_ ;-)

## Background Reading / Watching

+ Lunchdown: Deploying Elixir and Phoenix Applications
https://youtu.be/jOeR0kkUd7I
+ Elixir Forum Deployment Topic: https://elixirforum.com/c/popular-topics/deployment
+ Deploying Elixir applications with Edeliver:
http://blog.plataformatec.com.br/2016/06/deploying-elixir-applications-with-edeliver/
+ Getting Elixir / Phoenix running on Digital Ocean with edeliver:
https://gist.github.com/mattweldon/2e8ecb953216438ad168
(_links/packages are out-of-date but a good starting point_)
+ Is Phoenix deployment really that hard? http://cloudless.studio/articles/29-is-phoenix-deployment-really-that-hard
+ Elixir/Phoenix deployments using Distillery http://crypt.codemancers.com/posts/2016-10-06-elixir-phoenix-distillery/
+ Understanding `Mix.Tasks.Release.Init`
https://hexdocs.pm/distillery/Mix.Tasks.Release.Init.html
+ Elixir Phoenix App deployed into a Load Balanced DigitalOcean setup: http://www.akitaonrails.com/2016/12/23/elixir-phoenix-app-deployed-into-a-load-balanced-digitalocean-setup
+ Simplifying Elixir Releases With Edeliver: http://www.east5th.co/blog/2017/01/16/simplifying-elixir-releases-with-edeliver/
+ Running Elixir and Phoenix projects on a cluster of nodes:
https://dockyard.com/blog/2016/01/28/running-elixir-and-phoenix-projects-on-a-cluster-of-nodes
+ Clustering on EC2:
https://medium.com/@brucepomeroy/setting-up-and-elixir-cluster-on-ec2-with-edeliver-and-distillery-2500848cc34f
+ Hot code reloading with Erlang and Rebar3
https://medium.com/@kansi/hot-code-loading-with-erlang-and-rebar3-8252af16605b
+ Elixir/Phoenix deployments using Distillery http://crypt.codemancers.com/posts/2016-10-06-elixir-phoenix-distillery

## Frequently Asked/Answered Questions? (FAQ)

A few questions that came up while we were writing this post
and while other people were reading it ...
If **_you_** have **_any questions_**, please ask!

### Why Not Use Heroku?

Heroku is a _superb_ way to deploy your Phoenix App(s)
while in "Beta" because it has great _automatic
deployment_ (hooks) from GitHub, good logging etc.

If your Product Owner / Client Stake Holders `require`
you to deploy to a different environment,
then you need to get "_advanced_".

> If you are just starting out deploying Phoenix,
we _strongly **recommend**_ sticking with Heroku. <br />
(_debugging DevOps deployments isn't a "fun" activity,
so save it for later!_ ;-) <br />
Please see:
[github.com/dwyl/**learn-heroku**](https://github.com/dwyl/learn-heroku)
(_beginner's guide to deploying on Heroku_) <br />
and Phoenix _specific_
[/**heroku-deployment**.md](https://github.com/dwyl/learn-phoenix-framework/blob/master/heroku-deployment.md)

Trouble-shooting:

check app running:

```
lsof -i :4000
```
