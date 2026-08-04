defmodule Ecto.Integration.SandboxTest do
  use ExUnit.Case

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Integration.{PoolRepo, TestRepo}
  alias Ecto.Integration.Post

  import ExUnit.CaptureLog

  Application.put_env(:ecto_sql, __MODULE__.DynamicRepo, Application.compile_env(:ecto_sql, TestRepo))

  defmodule DynamicRepo do
    use Ecto.Repo, otp_app: :ecto_sql, adapter: TestRepo.__adapter__()
  end

  describe "errors" do
    test "raises if repo doesn't exist" do
      assert_raise UndefinedFunctionError, ~r"function UnknownRepo.get_dynamic_repo/0 is undefined", fn ->
        Sandbox.mode(UnknownRepo, :manual)
      end
    end

    test "raises if repo is not started" do
      assert_raise RuntimeError, ~r"could not lookup Ecto repo #{inspect DynamicRepo} because it was not started", fn ->
        Sandbox.mode(DynamicRepo, :manual)
      end
    end

    test "raises if repo is not using sandbox" do
      assert_raise RuntimeError, ~r"cannot invoke sandbox operation with pool DBConnection", fn ->
        Sandbox.mode(PoolRepo, :manual)
      end

      assert_raise RuntimeError, ~r"cannot invoke sandbox operation with pool DBConnection", fn ->
        Sandbox.checkout(PoolRepo)
      end
    end

    test "includes link to SQL sandbox on ownership errors" do
      assert_raise DBConnection.OwnershipError,
               ~r"See Ecto.Adapters.SQL.Sandbox docs for more information.", fn ->
        TestRepo.all(Post)
      end
    end
  end

  describe "mode" do
    test "uses the repository when checked out" do
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end
      Sandbox.checkout(TestRepo)
      assert TestRepo.all(Post) == []
      Sandbox.checkin(TestRepo)
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end
    end

    test "uses the repository when allowed from another process" do
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end

      parent = self()

      Task.start_link fn ->
        Sandbox.checkout(TestRepo)
        Sandbox.allow(TestRepo, self(), parent)
        send(parent, :allowed)
        Process.sleep(:infinity)
      end

      assert_receive :allowed
      assert TestRepo.all(Post) == []
    end

    test "uses the repository when allowed from another process by registered name" do
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end

      parent = self()
      Process.register(parent, __MODULE__)

      Task.start_link fn ->
        Sandbox.checkout(TestRepo)
        Sandbox.allow(TestRepo, self(), __MODULE__)
        send(parent, :allowed)
        Process.sleep(:infinity)
      end

      assert_receive :allowed
      assert TestRepo.all(Post) == []

      Process.unregister(__MODULE__)
    end

    test "uses the repository when shared from another process" do
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end

      parent = self()

      Task.start_link(fn ->
        Sandbox.checkout(TestRepo)
        Sandbox.mode(TestRepo, {:shared, self()})
        send(parent, :shared)
        Process.sleep(:infinity)
      end)

      assert_receive :shared
      assert Task.async(fn -> TestRepo.all(Post) end) |> Task.await == []
    after
      Sandbox.mode(TestRepo, :manual)
    end

    test "works with a dynamic repo" do
      repo_pid = start_supervised!({DynamicRepo, name: nil})
      DynamicRepo.put_dynamic_repo(repo_pid)

      assert Sandbox.mode(DynamicRepo, :manual) == :ok

      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        DynamicRepo.all(Post)
      end

      Sandbox.checkout(DynamicRepo)
      assert DynamicRepo.all(Post) == []
    end

    test "works with a repo pid" do
      repo_pid = start_supervised!({DynamicRepo, name: nil})
      DynamicRepo.put_dynamic_repo(repo_pid)

      assert Sandbox.mode(repo_pid, :manual) == :ok

      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        DynamicRepo.all(Post)
      end

      Sandbox.checkout(repo_pid)
      assert DynamicRepo.all(Post) == []
    end
  end

  describe "savepoints" do
    test "runs inside a sandbox that is rolled back on checkin" do
      Sandbox.checkout(TestRepo)
      assert TestRepo.insert(%Post{})
      assert TestRepo.all(Post) != []
      Sandbox.checkin(TestRepo)
      Sandbox.checkout(TestRepo)
      assert TestRepo.all(Post) == []
      Sandbox.checkin(TestRepo)
    end

    test "runs inside a sandbox that may be disabled" do
      Sandbox.checkout(TestRepo, sandbox: false)
      assert TestRepo.insert(%Post{})
      assert TestRepo.all(Post) != []
      Sandbox.checkin(TestRepo)

      Sandbox.checkout(TestRepo)
      assert {1, _} = TestRepo.delete_all(Post)
      Sandbox.checkin(TestRepo)

      Sandbox.checkout(TestRepo, sandbox: false)
      assert {1, _} = TestRepo.delete_all(Post)
      Sandbox.checkin(TestRepo)
    end

    test "runs inside a sandbox with caller data when preloading associations" do
      Sandbox.checkout(TestRepo)
      assert TestRepo.insert(%Post{})
      parent = self()

      Task.start_link fn ->
        Sandbox.allow(TestRepo, parent, self())
        assert [_] = TestRepo.all(Post) |> TestRepo.preload([:author, :comments])
        send parent, :success
      end

      assert_receive :success
    end

    test "runs inside a sidebox with custom ownership timeout" do
      :ok = Sandbox.checkout(TestRepo, ownership_timeout: 200)
      parent = self()

      assert capture_log(fn ->
        {:ok, pid} =
          Task.start(fn ->
            Sandbox.allow(TestRepo, parent, self())
            TestRepo.transaction(fn -> Process.sleep(500) end)
          end)

        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, _, ^pid, _}, 1000
      end) =~ "it owned the connection for longer than 200ms"
    end

    test "does not taint the sandbox on query errors" do
      Sandbox.checkout(TestRepo)

      {:ok, _}    = TestRepo.insert(%Post{}, skip_transaction: true)
      {:error, _} = TestRepo.query("INVALID")
      {:ok, _}    = TestRepo.insert(%Post{}, skip_transaction: true)

      Sandbox.checkin(TestRepo)
    end
  end

  describe "transactions" do
    @tag :transaction_isolation
    test "with custom isolation level" do
      Sandbox.checkout(TestRepo, isolation: "READ UNCOMMITTED")

      # Setting it to the same level later on works
      TestRepo.query!("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED")

      # Even inside a transaction
      TestRepo.transaction fn ->
        TestRepo.query!("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED")
      end
    end

    test "disconnects on transaction timeouts" do
      Sandbox.checkout(TestRepo)

      assert capture_log(fn ->
        {:error, :rollback} =
          TestRepo.transaction(fn -> Process.sleep(1000) end, timeout: 100)
      end) =~ "timed out"

      Sandbox.checkin(TestRepo)
    end
  end

  describe "checkouts" do
    test "with transaction inside checkout" do
      Sandbox.checkout(TestRepo)
      refute TestRepo.checked_out?()
      refute TestRepo.in_transaction?()

      TestRepo.checkout(fn ->
        assert TestRepo.checked_out?()
        refute TestRepo.in_transaction?()
        TestRepo.transaction(fn ->
          assert TestRepo.checked_out?()
          assert TestRepo.in_transaction?()
        end)
        assert TestRepo.checked_out?()
        refute TestRepo.in_transaction?()
      end)

      refute TestRepo.checked_out?()
      refute TestRepo.in_transaction?()
    end

    test "with checkout inside transaction" do
      Sandbox.checkout(TestRepo)
      refute TestRepo.checked_out?()
      refute TestRepo.in_transaction?()

      TestRepo.transaction(fn ->
        assert TestRepo.checked_out?()
        assert TestRepo.in_transaction?()
        TestRepo.checkout(fn ->
          assert TestRepo.checked_out?()
          assert TestRepo.in_transaction?()
        end)
        assert TestRepo.checked_out?()
        assert TestRepo.in_transaction?()
      end)

      refute TestRepo.checked_out?()
      refute TestRepo.in_transaction?()
    end
  end

  describe "start_owner!/2" do
    test "checks out the connection" do
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end

      owner = Sandbox.start_owner!(TestRepo)
      assert TestRepo.all(Post) == []

      :ok = Sandbox.stop_owner(owner)
      refute Process.alive?(owner)
    end

    test "can set shared mode" do
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end

      parent = self()

      Task.start_link(fn ->
        owner = Sandbox.start_owner!(TestRepo, shared: true)
        send(parent, {:owner, owner})
        Process.sleep(:infinity)
      end)

      assert_receive {:owner, owner}
      assert TestRepo.all(Post) == []
      :ok = Sandbox.stop_owner(owner)
    after
      Sandbox.mode(TestRepo, :manual)
    end
  end
end
