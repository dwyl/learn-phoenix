defmodule InfoSysTest do
  use ExUnit.Case
  alias InfoSys.Result

  defmodule TestBackend do
    def start_link(query, ref, owner, limit) do
      Task.start_link(__MODULE__, :fetch, [query, ref, owner, limit])
    end
    def fetch("result", ref, owner, __limit) do
      send(owner, {:results, ref, [%Result{backend: "test", text: "result"}]})
    end
    def fetch("none", ref, owner, __limit) do
      send(owner, {:results, ref, []})
    end
    def fetch("timeout", _ref, owner, _limit) do
      send(owner, {:backend, self()})
      :timer.sleep(:infinity) # p.242
    end
    def fetch("boom", _ref, _owner, _limit) do
      raise "boom!"
    end
  end

  test "compute/2 with backend results" do
    assert [%Result{backend: "test", text: "result"}] =
      InfoSys.compute("result", backends: [TestBackend])
  end

  test "compute/2 with no backend results" do
    assert [] = InfoSys.compute("none", backends: [TestBackend])
  end

  test "compute/2 with timeout returns no results and kills workers" do
    results = InfoSys.compute("timeout", backends: [TestBackend], timeout: 10)
    assert results == []
    assert_receive {:backend, backend_pid}
    ref = Process.monitor(backend_pid)
    assert_receive {:DOWN, ^ref, :process, _pid, _reason}
    refute_received {:DOWN, _, _, _, _}
    refute_received :timedout
  end

  @tag :capture_log
  test "compute/2 discards backend errors" do
    assert InfoSys.compute("boom", backends: [TestBackend]) == []
    refute_received {:DOWN, _, _, _, _}
    refute_received :timedout
  end
end
