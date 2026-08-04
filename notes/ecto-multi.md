# Using Ecto.Multi

### What?

`Ecto.Multi` is a data structure for grouping multiple Repo operations.
It allows you to run operations together that should be performed in a single
database transaction. You can see the result of each operation, before it
goes through.

### Why?

Here's the situation: Let's say you are building a chat application that has
users who can choose to connect together. When they choose to connect, a room
is created and they are added to the room.

We want to ensure this happens all at once. We don't want users to connect if
there is an error in creating the room. Likewise, we don't want a room created
when the users fail to connect!

One way this might be done is nested `cases`...

```elixir

alias App.{Relationship, Room}

relationship_changeset = Relationship.changeset(%Relationship{}, relationship_params)
case Repo.insert(changeset) do
  {:ok, relationship} ->
    room_changeset = %Room{
      user_id: relationship.user_id,
      friend_id: relationship.friend_id,
      name: "room:" <> to_string(relationship.user_id) <> " and " to_string(relationship.friend_id)
    }
    case Repo.insert(room_changeset) do
      {:ok, room} ->
        conn
        |> put_flash(:info, "Yay! Start chatting to your new friend!")
        |> redirect(to: room_path(conn, :show, room))
      {:error, changeset} ->
        Repo.delete(relationship)
        conn
        |> put_flash(:error, "Couldn't connect as friends :(. Try again later")
        |> render("new.html", changeset: changeset)
    end
  {:error, changeset} ->
    conn
    |> put_flash(:error, "Couldn't connect as friends :(. Try again later")
    |> render("new.html", changeset: changeset)
end
```

That's one way to do it, but

![ew gif](https://media.giphy.com/media/8OWujg6evVhsc/giphy.gif)

This is with only *two* `Repo.insert`s, so this gets **really** messy,
**really** fast. We also have to do *another* database operation if the room
creation fails so we can delete the relationship. Wouldn't it be much better if
we can rollback the entire transaction if anything fails, and be told exactly
where it fails?

### How?

`Ecto.Multi` does *precisely* that! The above example can be rewritten as:

```elixir

alias App.{Relationship, Room}
alias Ecto.Multi

relationship_changeset = Relationship.changeset(%Relationship{}, relationship_params)
multi =
  Multi.new
  |> Multi.insert(:relationship, relationship_changeset)
  |> Multi.run(:room, fn %{relationship: relationship} ->
    room_changeset = %Room{
      user_id: relationship.user_id,
      friend_id: relationship.friend_id,
      name: "room:" <> to_string(relationship.user_id) <> " and " to_string(relationship.friend_id)
    }
    Repo.insert(room_changeset)
  end)

case Repo.transaction(multi) do
  {:ok, room} ->
    conn
    |> put_flash(:info, "Yay! Start chatting to your new friend!")
    |> redirect(to: room_path(conn, :show, room))
  {:error, :relationship, changeset, _} ->
    conn
    |> put_flash(:error, "Couldn't connect as friends :(. Try again later")
    |> render("new.html", changeset: changeset)
  {:error, :room, changeset, _} ->
    conn
    |> put_flash(:error, "Couldn't connect as friends :(. Try again later")
    |> render("new.html", changeset: changeset)
end
```

![beautiful gif](https://media.giphy.com/media/V4Qwt8nNaf2xO/giphy.gif)

Although this may be approximately the same number of lines of code, it is
much more readable. The possible errors in `Repo.transaction(multi)` tell us
where in the operation the error occurred. Better errors leads to easier
debugging!

A function to create the `multi` can (and should) even be moved to another
file to separate the logic for the `multi` and the `Repo` operations. This
will clean things up even more!

`other_file.ex`
```elixir

def create_relationship_and_rooms(relationship_changeset) do
  Multi.new
  |> Multi.insert(:relationship, relationship_changeset)
  |> Multi.run(:room, fn %{relationship: relationship} ->
    room_changeset = %Room{
      user_id: relationship.user_id,
      friend_id: relationship.friend_id,
      name: "room:" <> to_string(relationship.user_id) <> " and " to_string(relationship.friend_id)
    }
    Repo.insert(room_changeset)
  end
end
```


`original_file.ex`
```elixir

relationship_changeset = Relationship.changeset(%Relationship{}, relationship_params)
multi = OtherFile.create_relationship_and_rooms(relationship_changeset)

case Repo.transaction(multi) do
  {:ok, room} ->
    conn
    |> put_flash(:info, "Yay! Start chatting to your new friend!")
    |> redirect(to: room_path(conn, :show, room))
  {:error, :relationship, changeset, _} ->
    conn
    |> put_flash(:error, "Couldn't connect as friends :(. Try again later")
    |> render("new.html", changeset: changeset)
  {:error, :room, changeset, _} ->
    conn
    |> put_flash(:error, "Couldn't connect as friends :(. Try again later")
    |> render("new.html", changeset: changeset)
end
```


This highlights the improvement even more :tada: :heart_eyes:! Hope you enjoy
using `Ecto.Multi`!

### Helpful resources

* [Ecto.Multi docs](https://hexdocs.pm/ecto/Ecto.Multi.html)
* [Blog on Multi](http://blog.danielberkompas.com/2016/09/27/ecto-multi-services.html)
* [Production example of Ecto.Multi](https://github.com/healthlocker/healthlocker/blob/master/lib/healthlocker/slam/connect_carer.ex)
