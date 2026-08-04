defmodule Ecto.Integration.TransactionTest do
  # We can keep this test async as long as it
  # is the only one access the transactions table
  use Ecto.Integration.Case, async: true

  import Ecto.Query
  alias Ecto.Integration.PoolRepo # Used for writes
  alias Ecto.Integration.TestRepo # Used for reads

  @moduletag :capture_log

  defmodule UniqueError do
    defexception message: "unique error"
  end

  setup do
    PoolRepo.delete_all "transactions"
    :ok
  end

  defmodule Trans do
    use Ecto.Schema

    schema "transactions" do
      field :num, :integer
    end
  end

  test "transaction returns value" do
    refute PoolRepo.in_transaction?()
    {:ok, val} = PoolRepo.transaction(fn ->
      assert PoolRepo.in_transaction?()
      {:ok, val} =
        PoolRepo.transaction(fn ->
          assert PoolRepo.in_transaction?()
          42
        end)
      assert PoolRepo.in_transaction?()
      val
    end)
    refute PoolRepo.in_transaction?()
    assert val == 42
  end

  test "transaction re-raises" do
    assert_raise UniqueError, fn ->
      PoolRepo.transaction(fn ->
        PoolRepo.transaction(fn ->
          raise UniqueError
        end)
      end)
    end
  end

  # tag is required for TestRepo, since it is checkout in
  # Ecto.Integration.Case setup
  @tag isolation_level: :snapshot
  test "transaction commits" do
    # mssql requires that all transactions that use same shared lock are set
    # to :snapshot isolation level
    opts = [isolation_level: :snapshot]

    PoolRepo.transaction(fn ->
      e = PoolRepo.insert!(%Trans{num: 1})
      assert [^e] = PoolRepo.all(Trans)
      assert [] = TestRepo.all(Trans)
    end, opts)

    assert [%Trans{num: 1}] = PoolRepo.all(Trans)
  end

  @tag isolation_level: :snapshot
  test "transaction rolls back" do
    opts = [isolation_level: :snapshot]
    try do
      PoolRepo.transaction(fn ->
        e = PoolRepo.insert!(%Trans{num: 2})
        assert [^e] = PoolRepo.all(Trans)
        assert [] = TestRepo.all(Trans)
        raise UniqueError
      end, opts)
    rescue
      UniqueError -> :ok
    end

    assert [] = TestRepo.all(Trans)
  end

  test "transaction rolls back per repository" do
    message = "cannot call rollback outside of transaction"

    assert_raise RuntimeError, message, fn ->
      PoolRepo.rollback(:done)
    end

    assert_raise RuntimeError, message, fn ->
      TestRepo.transaction fn ->
        PoolRepo.rollback(:done)
      end
    end
  end

  @tag :assigns_id_type
  test "transaction rolls back with reason on aborted transaction" do
    e1 = PoolRepo.insert!(%Trans{num: 13})

    assert_raise Ecto.ConstraintError, fn ->
      TestRepo.transaction fn ->
        PoolRepo.insert!(%Trans{id: e1.id, num: 14})
      end
    end
  end

  test "nested transaction partial rollback" do
    assert PoolRepo.transaction(fn ->
      e1 = PoolRepo.insert!(%Trans{num: 3})
      assert [^e1] = PoolRepo.all(Trans)

      try do
        PoolRepo.transaction(fn ->
          e2 = PoolRepo.insert!(%Trans{num: 4})
          assert [^e1, ^e2] = PoolRepo.all(from(t in Trans, order_by: t.num))
          raise UniqueError
        end)
      rescue
        UniqueError -> :ok
      end

      assert_raise DBConnection.ConnectionError, "transaction rolling back",
        fn() -> PoolRepo.insert!(%Trans{num: 5}) end
    end) == {:error, :rollback}

    assert TestRepo.all(Trans) == []
  end

  test "manual rollback doesn't bubble up" do
    x = PoolRepo.transaction(fn ->
      e = PoolRepo.insert!(%Trans{num: 6})
      assert [^e] = PoolRepo.all(Trans)
      PoolRepo.rollback(:oops)
    end)

    assert x == {:error, :oops}
    assert [] = TestRepo.all(Trans)
  end

  test "manual rollback bubbles up on nested transaction" do
    assert PoolRepo.transaction(fn ->
      e = PoolRepo.insert!(%Trans{num: 7})
      assert [^e] = PoolRepo.all(Trans)
      assert {:error, :oops} = PoolRepo.transaction(fn ->
        PoolRepo.rollback(:oops)
      end)
      assert_raise DBConnection.ConnectionError, "transaction rolling back",
        fn() -> PoolRepo.insert!(%Trans{num: 8}) end
    end) == {:error, :rollback}

    assert [] = TestRepo.all(Trans)
  end

  test "transactions are not shared in repo" do
    pid = self()
    opts = [isolation_level: :snapshot]

    new_pid = spawn_link fn ->
      PoolRepo.transaction(fn ->
        e = PoolRepo.insert!(%Trans{num: 9})
        assert [^e] = PoolRepo.all(Trans)
        send(pid, :in_transaction)
        receive do
          :commit -> :ok
        after
          5000 -> raise "timeout"
        end
      end, opts)
      send(pid, :committed)
    end

    receive do
      :in_transaction -> :ok
    after
      5000 -> raise "timeout"
    end

    # mssql requires that all transactions that use same shared lock
    # set transaction isolation level to "snapshot" so this must be wrapped into
    # explicit transaction
    PoolRepo.transaction(fn ->
      assert [] = PoolRepo.all(Trans)
    end, opts)

    send(new_pid, :commit)
    receive do
      :committed -> :ok
    after
      5000 -> raise "timeout"
    end

    assert [%Trans{num: 9}] = PoolRepo.all(Trans)
  end

  ## Checkout

  describe "with checkouts" do
    test "transaction inside checkout" do
      PoolRepo.checkout(fn ->
        refute PoolRepo.in_transaction?()
        PoolRepo.transaction(fn ->
          assert PoolRepo.in_transaction?()
        end)
        refute PoolRepo.in_transaction?()
      end)
    end

    test "checkout inside transaction" do
      PoolRepo.transaction(fn ->
        assert PoolRepo.in_transaction?()
        PoolRepo.checkout(fn ->
          assert PoolRepo.in_transaction?()
        end)
        assert PoolRepo.in_transaction?()
      end)
    end

    @tag :transaction_checkout_raises
    test "checkout raises on transaction attempt" do
      assert_raise DBConnection.ConnectionError, ~r"connection was checked out with status", fn ->
        PoolRepo.checkout(fn -> PoolRepo.query!("BEGIN") end)
      end
    end
  end

  ## Logging

  defp register_telemetry() do
    Process.put(:telemetry, fn _, measurements, event -> send(self(), {measurements, event}) end)
  end

  test "log begin, commit and rollback" do
    register_telemetry()

    PoolRepo.transaction(fn ->
      assert_received {measurements, %{params: [], result: {:ok, _res}}}
      assert is_integer(measurements.query_time) and measurements.query_time >= 0
      assert is_integer(measurements.queue_time) and measurements.queue_time >= 0

      refute_received %{}
      register_telemetry()
    end)

    assert_received {measurements, %{params: [], result: {:ok, _res}}}
    assert is_integer(measurements.query_time) and measurements.query_time >= 0
    refute Map.has_key?(measurements, :queue_time)

    assert PoolRepo.transaction(fn ->
      refute_received %{}
      register_telemetry()
      PoolRepo.rollback(:log_rollback)
    end) == {:error, :log_rollback}

    assert_received {measurements, %{params: [], result: {:ok, _res}}}
    assert is_integer(measurements.query_time) and measurements.query_time >= 0
    refute Map.has_key?(measurements, :queue_time)
  end

  test "log queries inside transactions" do
    PoolRepo.transaction(fn ->
      register_telemetry()
      assert [] = PoolRepo.all(Trans)

      assert_received {measurements, %{params: [], result: {:ok, _res}}}
      assert is_integer(measurements.query_time) and measurements.query_time >= 0
      assert is_integer(measurements.decode_time) and measurements.query_time >= 0
      refute Map.has_key?(measurements, :queue_time)
    end)
  end
end
