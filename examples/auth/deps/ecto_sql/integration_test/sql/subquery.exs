defmodule Ecto.Integration.SubQueryTest do
  use Ecto.Integration.Case, async: Application.compile_env(:ecto, :async_integration_tests, true)

  alias Ecto.Integration.TestRepo
  import Ecto.Query
  alias Ecto.Integration.Post
  alias Ecto.Integration.Comment

  test "from: subqueries with select source" do
    TestRepo.insert!(%Post{title: "hello", public: true})

    query = from p in Post, select: p
    assert ["hello"] =
           TestRepo.all(from p in subquery(query), select: p.title)
    assert [post] =
           TestRepo.all(from p in subquery(query), select: p)

    assert %NaiveDateTime{} = post.inserted_at
    assert post.__meta__.state == :loaded
  end

  @tag :map_boolean_in_expression
  test "from: subqueries with map and select expression" do
    TestRepo.insert!(%Post{title: "hello", public: true})

    query = from p in Post, select: %{title: p.title, pub: not p.public}
    assert ["hello"] =
           TestRepo.all(from p in subquery(query), select: p.title)
    assert [%{title: "hello", pub: false}] =
           TestRepo.all(from p in subquery(query), select: p)
    assert [{"hello", %{title: "hello", pub: false}}] =
           TestRepo.all(from p in subquery(query), select: {p.title, p})
    assert [{%{title: "hello", pub: false}, false}] =
           TestRepo.all(from p in subquery(query), select: {p, p.pub})
  end

  @tag :map_boolean_in_expression
  test "from: subqueries with map update and select expression" do
    TestRepo.insert!(%Post{title: "hello", public: true})

    query = from p in Post, select: %{p | public: not p.public}
    assert ["hello"] =
           TestRepo.all(from p in subquery(query), select: p.title)
    assert [%Post{title: "hello", public: false}] =
           TestRepo.all(from p in subquery(query), select: p)
    assert [{"hello", %Post{title: "hello", public: false}}] =
           TestRepo.all(from p in subquery(query), select: {p.title, p})
    assert [{%Post{title: "hello", public: false}, false}] =
           TestRepo.all(from p in subquery(query), select: {p, p.public})
  end

  test "from: subqueries with map update on virtual field and select expression" do
    TestRepo.insert!(%Post{title: "hello"})

    query = from p in Post, select: %{p | temp: p.title}
    assert ["hello"] =
           TestRepo.all(from p in subquery(query), select: p.temp)
    assert [%Post{title: "hello", temp: "hello"}] =
           TestRepo.all(from p in subquery(query), select: p)
  end

  @tag :subquery_aggregates
  test "from: subqueries with aggregates" do
    TestRepo.insert!(%Post{visits: 10})
    TestRepo.insert!(%Post{visits: 11})
    TestRepo.insert!(%Post{visits: 13})

    query = from p in Post, select: [:visits], order_by: [asc: :visits]
    assert [13] = TestRepo.all(from p in subquery(query), select: max(p.visits))
    query = from p in Post, select: [:visits], order_by: [asc: :visits], limit: 2
    assert [11] = TestRepo.all(from p in subquery(query), select: max(p.visits))

    query = from p in Post, order_by: [asc: :visits]
    assert [13] = TestRepo.all(from p in subquery(query), select: max(p.visits))
    query = from p in Post, order_by: [asc: :visits], limit: 2
    assert [11] = TestRepo.all(from p in subquery(query), select: max(p.visits))
  end

  test "from: subqueries with parameters" do
    TestRepo.insert!(%Post{visits: 10, title: "hello"})
    TestRepo.insert!(%Post{visits: 11, title: "hello"})
    TestRepo.insert!(%Post{visits: 13, title: "world"})

    query = from p in Post, where: p.visits >= ^11 and p.visits <= ^13
    query = from p in subquery(query), where: p.title == ^"hello", select: fragment("? + ?", p.visits, ^1)
    assert [12] = TestRepo.all(query)
  end

  test "join: subqueries with select source" do
    %{id: id} = TestRepo.insert!(%Post{title: "hello", public: true})
    TestRepo.insert!(%Comment{post_id: id})

    query = from p in Post, select: p
    assert ["hello"] =
           TestRepo.all(from c in Comment, join: p in subquery(query), on: c.post_id == p.id, select: p.title)
    assert [%Post{inserted_at: %NaiveDateTime{}}] =
           TestRepo.all(from c in Comment, join: p in subquery(query), on: c.post_id == p.id, select: p)
  end

  test "join: subqueries with parameters" do
    TestRepo.insert!(%Post{visits: 10, title: "hello"})
    TestRepo.insert!(%Post{visits: 11, title: "hello"})
    TestRepo.insert!(%Post{visits: 13, title: "world"})
    TestRepo.insert!(%Comment{})
    TestRepo.insert!(%Comment{})

    query = from p in Post, where: p.visits >= ^11 and p.visits <= ^13
    query = from c in Comment,
              join: p in subquery(query),
              on: true,
              where: p.title == ^"hello",
              select: fragment("? + ?", p.visits, ^1)
    assert [12, 12] = TestRepo.all(query)
  end

  @tag :subquery_in_order_by
  test "subqueries in order by" do
    TestRepo.insert!(%Post{visits: 10, title: "hello"})
    TestRepo.insert!(%Post{visits: 11, title: "hello"})

    query = from p in Post, as: :p, order_by: [asc: exists(from p in Post, where: p.visits > parent_as(:p).visits)]

    assert [%{visits: 11}, %{visits: 10}] = TestRepo.all(query)
  end

  @tag :multicolumn_distinct
  @tag :subquery_in_distinct
  test "subqueries in distinct" do
    TestRepo.insert!(%Post{visits: 10, title: "hello1"})
    TestRepo.insert!(%Post{visits: 10, title: "hello2"})
    TestRepo.insert!(%Post{visits: 11, title: "hello"})

    query = from p in Post, as: :p, distinct: exists(from p in Post, where: p.visits > parent_as(:p).visits), order_by: [asc: :title]

    assert [%{title: "hello"}, %{title: "hello1"}] = TestRepo.all(query)
  end

  @tag :subquery_in_group_by
  test "subqueries in group by" do
    TestRepo.insert!(%Post{visits: 10, title: "hello1"})
    TestRepo.insert!(%Post{visits: 10, title: "hello2"})
    TestRepo.insert!(%Post{visits: 11, title: "hello"})

    query = from p in Post, as: :p, select: sum(p.visits), group_by: exists(from p in Post, where: p.visits > parent_as(:p).visits), order_by: [sum(p.visits)]

    query
    |> TestRepo.all()
    |> Enum.map(&Decimal.new/1)
    |> Enum.zip([Decimal.new(11), Decimal.new(20)])
    |> Enum.all?(fn {a, b} -> Decimal.eq?(a, b) end)
    |> assert()
  end
end
