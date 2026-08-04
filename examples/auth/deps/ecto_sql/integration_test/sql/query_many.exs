defmodule Ecto.Integration.QueryManyTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo

  test "query_many!/4" do
    results = TestRepo.query_many!("SELECT 1; SELECT 2;")
    assert  [%{rows: [[1]], num_rows: 1}, %{rows: [[2]], num_rows: 1}] = results
  end

  test "query_many!/4 with iodata" do
    results = TestRepo.query_many!(["SELECT", ?\s, ?1, ";", ?\s, "SELECT", ?\s, ?2, ";"])
    assert  [%{rows: [[1]], num_rows: 1}, %{rows: [[2]], num_rows: 1}] = results
  end
end
