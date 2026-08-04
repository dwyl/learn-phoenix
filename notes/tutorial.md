So we have already covered the basics to get your phoenix server up and running:
```bash
$ mix phoenix.new blog
$ cd blog
$ mix ecto.create
```

We are going to use the phoenix generators to generate some routes, controllers, views and postgres tables needed to create a blogging platform. There will be a lot of magic.


Since we are creating a blogging platform, we will need a `posts` table, which has two columns: `title` & `body`. `Post` (singular) will be used to generate the files and module. In the terminal, run:
```bash
$ mix phoenix.gen.html Post posts title:string body:text
```


Running this command will create the following files:
```
* creating web/controllers/post_controller.ex
* creating web/templates/post/edit.html.eex
* creating web/templates/post/form.html.eex
* creating web/templates/post/index.html.eex
* creating web/templates/post/new.html.eex
* creating web/templates/post/show.html.eex
* creating web/views/post_view.ex
* creating test/controllers/post_controller_test.exs
* creating web/models/post.ex
* creating test/models/post_test.exs
* creating priv/repo/migrations/20170206141541_create_post.exs
```

We will be covering a few of them in this README but first we will be starting with a file you should already have, `web/router.ex`. You will need to paste in the following code `resources "/posts", PostController`. It should look something like this

```elixir
scope "/", BlogPhoenix do
  pipe_through :browser # Use the default browser stack

  get "/", PageController, :index
  resources "/posts", PostController
end
```

Next we need to create our new table in postgres. in the terminal run:
```bash
$ mix ecto.migrate
```

____________________

## Adding draft functionality

Now we can start editing some of the newly created files. We can start by adding a draft checkbox to the form:
edit `/web/templates/post/form.html` add checkbox field

```html
  <div class="draft">
    <%= label f, :draft, class: "control-label" %>
    <%= checkbox f, :draft, class: "form-control" %>
    <%= error_tag f, :draft %>
  </div>
```

Now we can go to `localhost:4000/posts/new` and should be able to see the draft checkbox. If we tick the checkbox, add a title and body, and press submit then in the terminal you should see that the draft key value pair is in the form's payload, but it is not added to the database.

```elixir
"post" => %{"body" => "A body", "draft" => "true", "title" => "A title"}
```

In order to add the new column to our posts table, we need to edit our schema, and perform a migration.

In `web/models/post.ex`
- we want to add to our schema,
```elixir
schema "posts" do
  field :title, :string
  field :body, :string
  field :draft, :boolean
```

- and add the new draft field to our changeset function:
```elixir
def changeset(struct, params \\ %{}) do
  struct
  |> cast(params, [:title, :body, :draft])
  |> validate_required([:title, :body, :draft])
end
```

Now to perform the table migration

In the terminal, type:
```bash
$ mix ecto.gen.migration add_drafts_to_posts
```
This will create a new file in `priv/repo/migrations` with a time stamp, and the add_drafts_to_posts name. Inside this file, we want instruct postgres to alter our table. Update the `change` function definition:

```elixir
def change do
  alter table(:posts) do
    add :draft, :boolean
  end
end
```
[See the docs](https://hexdocs.pm/ecto/Ecto.Migration.html#add/3) if you want to understand more on the `add` function and the `alter` macro.


Now we need to implement that change on our database by running

```bash
$ mix ecto.migrate
```

Great, our table has been altered to allow for a `draft` entry. If we go through the flow of creating a new draft post again, we can see the following line in the terminal after pressing submit:

```sql
INSERT INTO "posts"
  ("body","draft","title","inserted_at","updated_at")
  VALUES ($1,$2,$3,$4,$5)
  RETURNING "id" ["jackem", true, "hey", {...}]
```

Now that we are storing the `draft` key in our database, we just need to display it on the front end.

In `web/templates/post/index.html.eex` we want to add a new `Draft` heading and the boolean value for each post, so add the following lines in their respective places:

```html
<th>Draft</th>
<td><%= post.draft %></td>
```

We also want to add this new info the the individual post view which is in the `web/templates/posts/show.html.eex`:
```html
  <li>
    <strong>Draft:</strong>
    <%= @post.draft %>
  </li>
```

Now you should be able to take a look around with your new draft functionality.

____________________

## Adding a new route (optional)

We will next add a new endpoint that lists only the drafts.
In `web/router.ex` we want to add a new `GET` route to our list of routes:

```elixir
get "/", PageController, :index
resources "/posts", PostController
```

Will become:

```elixir
get "/", PageController, :index
get "/posts/drafts", PostController, :drafts
resources "/posts", PostController
```

We now need to add a drafts function in our `PostController`
```elixir
  def drafts(conn, _params) do
    query = from post in Post, where: post.draft == true
    posts = Repo.all(query)
    render(conn, "index.html", posts: posts)
  end
```

The only difference between our new `draft` function and the `index` function that is already there is the `query`. Check out the query docs [here](https://hexdocs.pm/ecto/Ecto.Query.html). We use this to query the database and get all posts where draft is true. Go to the endpoint `/posts/drafts` to see this new view.

## TLDR

+ `mix phoenix.new blog`
+ `cd blog`
+ `mix ecto.create`
+ `mix phoenix.gen.html Post posts title:string body:text`
+ add route to `router.ex` file (`resources "/posts", PostController`)
+ `mix ecto.migrate` (generates the table)
+ add draft functionality to `/web/templates/post/form.html`
+ update `schema` and `changeset` function in `web/models/post.ex`
+ `mix ecto.gen.migration add_drafts_to_posts` (notice new file in `priv/rep/migrations` )
+ update `change` function in `priv/rep/migrations`
+ `mix ecto.migrate`
+ add the draft header to `/web/templates/show.html`
+ add the draft to `/web/templates/index.html`
