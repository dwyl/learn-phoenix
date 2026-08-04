defmodule Ecto.Integration.LoggingTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.PoolRepo
  alias Ecto.Integration.{Post, Logging, ArrayLogging}

  import ExUnit.CaptureLog
  import Ecto.Query, only: [from: 2]

  describe "telemetry" do
    test "dispatches event" do
      log = fn event_name, measurements, metadata ->
        assert Enum.at(event_name, -1) == :query
        assert %{result: {:ok, _res}} = metadata

        assert measurements.total_time ==
                 measurements.query_time + measurements.decode_time + measurements.queue_time

        assert measurements.idle_time
        send(self(), :logged)
      end

      Process.put(:telemetry, log)
      _ = PoolRepo.all(Post)
      assert_received :logged
    end

    test "dispatches event with stacktrace" do
      log = fn _event_name, _measurements, metadata ->
        assert %{stacktrace: [_ | _]} = metadata
        send(self(), :logged)
      end

      Process.put(:telemetry, log)
      _ = PoolRepo.all(Post, stacktrace: true)
      assert_received :logged
    end

    test "dispatches event with custom options" do
      log = fn event_name, _measurements, metadata ->
        assert Enum.at(event_name, -1) == :query
        assert metadata.options == [:custom_metadata]
        send(self(), :logged)
      end

      Process.put(:telemetry, log)
      _ = PoolRepo.all(Post, telemetry_options: [:custom_metadata])
      assert_received :logged
    end

    test "dispatches under another event name" do
      log = fn [:custom], measurements, metadata ->
        assert %{result: {:ok, _res}} = metadata

        assert measurements.total_time ==
                 measurements.query_time + measurements.decode_time + measurements.queue_time

        assert measurements.idle_time
        send(self(), :logged)
      end

      Process.put(:telemetry, log)
      _ = PoolRepo.all(Post, telemetry_event: [:custom])
      assert_received :logged
    end

    test "is not dispatched with no event name" do
      Process.put(:telemetry, fn _, _ -> raise "never called" end)
      _ = TestRepo.all(Post, telemetry_event: nil)
      refute_received :logged
    end

    test "cast params" do
      uuid_module =
        if TestRepo.__adapter__() == Ecto.Adapters.Tds do
          Tds.Ecto.UUID
        else
          Ecto.UUID
        end

      uuid = uuid_module.generate()
      dumped_uuid = uuid_module.dump!(uuid)

      log = fn _event_name, _measurements, metadata ->
        assert [dumped_uuid] == metadata.params
        assert [uuid] == metadata.cast_params
        send(self(), :logged)
      end

      Process.put(:telemetry, log)
      TestRepo.all(from l in Logging, where: l.uuid == ^uuid)
      assert_received :logged
    end
  end

  describe "logs" do
    @stacktrace_opts [stacktrace: true, log: :error]

    defp stacktrace_entry(line) do
      ~r/↳ anonymous fn\/0 in Ecto.Integration.LoggingTest.\"test logs includes stacktraces\"\/1, at: .*integration_test\/sql\/logging.exs:#{line - 3}/
    end

    test "when some measurements are nil" do
      assert capture_log(fn -> TestRepo.query("BEG", [], log: :error) end) =~
               "[error]"
    end

    test "includes stacktraces" do
      assert capture_log(fn ->
               TestRepo.all(Post, @stacktrace_opts)

               :ok
             end) =~ stacktrace_entry(__ENV__.line)

      assert capture_log(fn ->
               TestRepo.insert(%Post{}, @stacktrace_opts)

               :ok
             end) =~ stacktrace_entry(__ENV__.line)

      assert capture_log(fn ->
               # Test cascading options
               Ecto.Multi.new()
               |> Ecto.Multi.insert(:post, %Post{})
               |> TestRepo.transaction(@stacktrace_opts)

               :ok
             end) =~ stacktrace_entry(__ENV__.line)

      assert capture_log(fn ->
               # In theory we should point to the call _inside_ run
               # but all multi calls point to the transaction starting point.
               Ecto.Multi.new()
               |> Ecto.Multi.run(:all, fn _, _ -> {:ok, TestRepo.all(Post, @stacktrace_opts)} end)
               |> TestRepo.transaction()

               :ok
             end) =~ stacktrace_entry(__ENV__.line)

      out = capture_log(fn ->
               TestRepo.all(Post, Keyword.put(@stacktrace_opts, :log_stacktrace_mfa, {Ecto.Adapters.SQL, :first_non_ecto_stacktrace, [2]}))

               :ok
             end)

      assert out =~ stacktrace_entry(__ENV__.line - 2)

      # We are a bit liberal with what we expect as we don't want to tie to internal ExUnit code
      assert out =~ ~r/  ExUnit.CaptureLog.*/
    end

    test "with custom log level" do
      assert capture_log(fn -> TestRepo.insert!(%Post{title: "1"}, log: :error) end) =~
               "[error]"

      # We cannot assert on the result because it depends on the suite log level
      capture_log(fn ->
        TestRepo.insert!(%Post{title: "1"}, log: true)
      end)

      # But this assertion is always true
      assert capture_log(fn ->
               TestRepo.insert!(%Post{title: "1"}, log: false)
             end) == ""
    end

    test "with a log: true override when logging is disabled" do
      refute capture_log(fn ->
               TestRepo.insert!(%Post{title: "1"}, log: true)
             end) =~ "an exception was raised logging"
    end

    test "with unspecified :log option when logging is disabled" do
      refute capture_log(fn ->
               TestRepo.insert!(%Post{title: "1"})
             end) =~ "an exception was raised logging"
    end
  end

  describe "parameter logging" do
    @describetag :parameter_logging

    @uuid_regex ~r/[0-9a-f]{2}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
    @naive_datetime_regex ~r/~N\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]/

    test "for insert_all with query" do
      # Source query
      int = 1
      uuid = Ecto.UUID.generate()

      source_query =
        from l in Logging,
          where: l.int == ^int and l.uuid == ^uuid,
          select: %{uuid: l.uuid, int: l.int}

      # Ensure parameters are complete and in correct order
      log =
        capture_log(fn ->
          TestRepo.insert_all(Logging, source_query, log: :info)
        end)

      param_regex = ~r/\[(?<int>.+), \"(?<uuid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      # Query parameters
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
    end

    @tag :insert_select
    test "for insert_all with entries" do
      # Row 1
      int = 1
      uuid = Ecto.UUID.generate()
      uuid_query = from l in Logging, where: l.int == ^int and l.uuid == ^uuid, select: l.uuid
      datetime = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      row1 = [
        int: int,
        uuid: uuid_query,
        inserted_at: datetime,
        updated_at: datetime
      ]

      # Row 2
      int2 = 2
      uuid2 = Ecto.UUID.generate()
      int_query = from l in Logging, where: l.int == ^int2 and l.uuid == ^uuid2, select: l.int
      datetime2 = NaiveDateTime.add(datetime, 1)

      row2 = [
        int: int_query,
        uuid: uuid2,
        inserted_at: datetime2,
        updated_at: datetime2
      ]

      # Extract the parameters from the log:
      # 1. Remove the colour codes
      # 2. Remove the log level
      # 3. Capture everything inside of the square brackets
      log =
        capture_log(fn ->
          TestRepo.insert_all(Logging, [row1, row2], log: :info)
        end)

      log = Regex.replace(~r/\e\[[0-9]+m/, log, "")
      log = Regex.replace(~r/\[info\]/, log, "")
      log = Regex.named_captures(~r/\[(?<params>.+)\]/, log)
      log_params = String.split(log["params"], ",")

      # Compute the expected parameters in the right order.
      # This involves recreating the headers in the same order
      # as `insert_all`. The user values come first and then
      # the autogenerated id
      headers =
        row1
        |> Enum.reduce(%{}, fn {field, _}, headers -> Map.put(headers, field, true) end)
        |> Map.put(:bid, true)
        |> Map.keys()

      row1_regex = [
        int: "#{int}",
        uuid: ["#{int}", uuid],
        inserted_at: inspect(datetime),
        updated_at: inspect(datetime),
        bid: @uuid_regex
      ]

      row2_regex = [
        int: ["#{int2}", uuid2],
        uuid: uuid2,
        inserted_at: inspect(datetime2),
        updated_at: inspect(datetime2),
        bid: @uuid_regex
      ]

      expected_param_regex =
        Enum.flat_map([row1_regex, row2_regex], fn row ->
          Enum.flat_map(headers, fn field ->
            case Keyword.get(row, field) do
              params when is_list(params) -> params
              param -> [param]
            end
          end)
        end)

      assert length(log_params) == length(expected_param_regex)

      Enum.zip(log_params, expected_param_regex)
      |> Enum.each(fn {log, expected_regex} ->
        assert log =~ expected_regex
      end)
    end

    @tag :insert_select
    @tag :placeholders
    test "for insert_all with entries and placeholders" do
      # Placeholders
      datetime = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      datetime2 = NaiveDateTime.add(datetime, 1)
      placeholder_map = %{datetime: datetime, datetime2: datetime2}

      # Row 1
      int = 1
      uuid = Ecto.UUID.generate()
      uuid_query = from l in Logging, where: l.int == ^int and l.uuid == ^uuid, select: l.uuid

      row1 = [
        int: int,
        uuid: uuid_query,
        inserted_at: {:placeholder, :datetime},
        updated_at: {:placeholder, :datetime}
      ]

      # Row 2
      int2 = 2
      uuid2 = Ecto.UUID.generate()
      int_query = from l in Logging, where: l.int == ^int2 and l.uuid == ^uuid2, select: l.int

      row2 = [
        int: int_query,
        uuid: uuid2,
        inserted_at: {:placeholder, :datetime2},
        updated_at: {:placeholder, :datetime2}
      ]

      # Extract the parameters from the log:
      # 1. Remove the colour codes
      # 2. Remove the log level
      # 3. Capture everything inside of the square brackets
      log =
        capture_log(fn ->
          TestRepo.insert_all(Logging, [row1, row2],
            placeholders: placeholder_map,
            log: :info
          )
        end)

      log = Regex.replace(~r/\e\[[0-9]+m/, log, "")
      log = Regex.replace(~r/\[info\]/, log, "")
      log = Regex.named_captures(~r/\[(?<params>.+)\]/, log)
      log_params = String.split(log["params"], ",")

      # Compute the expected parameters in the right order.
      # This involves recreating the headers in the same order
      # as `insert_all`. The placeholders come first and then
      # the user values and then the autogenerated id
      headers =
        row1
        |> Enum.reduce(%{}, fn {field, _}, headers -> Map.put(headers, field, true) end)
        |> Map.put(:bid, true)
        |> Map.drop([:inserted_at, :updated_at])
        |> Map.keys()

      row1_regex = [
        int: "#{int}",
        uuid: ["#{int}", uuid],
        bid: @uuid_regex
      ]

      row2_regex = [
        int: ["#{int2}", uuid2],
        uuid: uuid2,
        bid: @uuid_regex
      ]

      row_param_regex =
        Enum.flat_map([row1_regex, row2_regex], fn row ->
          Enum.flat_map(headers, fn field ->
            case Keyword.get(row, field) do
              params when is_list(params) -> params
              param -> [param]
            end
          end)
        end)

      placeholder_regex = [inspect(datetime), inspect(datetime2)]
      expected_param_regex = placeholder_regex ++ row_param_regex

      assert length(log_params) == length(expected_param_regex)

      Enum.zip(log_params, expected_param_regex)
      |> Enum.each(fn {log, expected_regex} ->
        assert log =~ expected_regex
      end)
    end

    @tag :with_conflict_target
    test "for insert_all with query with conflict query" do
      # Source query
      int = 1
      uuid = Ecto.UUID.generate()

      source_query =
        from l in Logging,
          where: l.int == ^int and l.uuid == ^uuid,
          select: %{uuid: l.uuid, int: l.int}

      # Conflict query
      conflict_int = 0
      conflict_uuid = Ecto.UUID.generate()
      conflict_update = 2

      conflict_query =
        from l in Logging,
          where: l.int == ^conflict_int and l.uuid == ^conflict_uuid,
          update: [set: [int: ^conflict_update]]

      # Ensure parameters are complete and in correct order
      log =
        capture_log(fn ->
          TestRepo.insert_all(Logging, source_query,
            on_conflict: conflict_query,
            conflict_target: :bid,
            log: :info
          )
        end)

      param_regex =
        ~r/\[(?<int>.+), \"(?<uuid>.+)\", (?<conflict_update>.+), (?<conflict_int>.+), \"(?<conflict_uuid>.+)\"\]/

      param_logs = Regex.named_captures(param_regex, log)

      # Query parameters
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
      # Conflict query parameters
      assert param_logs["conflict_update"] == Integer.to_string(conflict_update)
      assert param_logs["conflict_int"] == Integer.to_string(conflict_int)
      assert param_logs["conflict_uuid"] == conflict_uuid
    end

    @tag :insert_select
    @tag :with_conflict_target
    test "for insert_all with entries conflict query" do
      # Row 1
      int = 1
      uuid = Ecto.UUID.generate()
      uuid_query = from l in Logging, where: l.int == ^int and l.uuid == ^uuid, select: l.uuid
      datetime = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      row1 = [
        int: int,
        uuid: uuid_query,
        inserted_at: datetime,
        updated_at: datetime
      ]

      # Row 2
      int2 = 2
      uuid2 = Ecto.UUID.generate()
      int_query = from l in Logging, where: l.int == ^int2 and l.uuid == ^uuid2, select: l.int
      datetime2 = NaiveDateTime.add(datetime, 1)

      row2 = [
        int: int_query,
        uuid: uuid2,
        inserted_at: datetime2,
        updated_at: datetime2
      ]

      # Conflict query
      conflict_int = 0
      conflict_uuid = Ecto.UUID.generate()
      conflict_update = 2

      conflict_query =
        from l in Logging,
          where: l.int == ^conflict_int and l.uuid == ^conflict_uuid,
          update: [set: [int: ^conflict_update]]

      # Extract the parameters from the log:
      # 1. Remove the colour codes
      # 2. Remove the log level
      # 3. Capture everything inside of the square brackets
      log =
        capture_log(fn ->
          TestRepo.insert_all(Logging, [row1, row2],
            on_conflict: conflict_query,
            conflict_target: :bid,
            log: :info
          )
        end)

      log = Regex.replace(~r/\e\[[0-9]+m/, log, "")
      log = Regex.replace(~r/\[info\]/, log, "")
      log = Regex.named_captures(~r/\[(?<params>.+)\]/, log)
      log_params = String.split(log["params"], ",")

      # Compute the expected parameters in the right order.
      # This involves recreating the headers in the same order
      # as `insert_all`. The user values come first, then
      # the autogenerated id and then the conflict params
      headers =
        row1
        |> Enum.reduce(%{}, fn {field, _}, headers -> Map.put(headers, field, true) end)
        |> Map.put(:bid, true)
        |> Map.keys()

      row1_regex = [
        int: "#{int}",
        uuid: ["#{int}", uuid],
        bid: @uuid_regex,
        inserted_at: inspect(datetime),
        updated_at: inspect(datetime)
      ]

      row2_regex = [
        int: ["#{int2}", uuid2],
        uuid: uuid2,
        bid: @uuid_regex,
        inserted_at: inspect(datetime2),
        updated_at: inspect(datetime2)
      ]

      row_param_regex =
        Enum.flat_map([row1_regex, row2_regex], fn row ->
          Enum.flat_map(headers, fn field ->
            case Keyword.get(row, field) do
              row_params when is_list(row_params) -> row_params
              row_param -> [row_param]
            end
          end)
        end)

      conflict_param_regex = ["#{conflict_update}", "#{conflict_int}", conflict_uuid]
      expected_param_regex = row_param_regex ++ conflict_param_regex

      assert length(log_params) == length(expected_param_regex)

      Enum.zip(log_params, expected_param_regex)
      |> Enum.each(fn {log, expected_regex} ->
        assert log =~ expected_regex
      end)
    end

    @tag :insert_select
    @tag :placeholders
    @tag :with_conflict_target
    test "for insert_all with entries, placeholders and conflict query" do
      # Row 1
      int = 1
      uuid = Ecto.UUID.generate()
      uuid_query = from l in Logging, where: l.int == ^int and l.uuid == ^uuid, select: l.uuid

      row1 = [
        int: int,
        uuid: uuid_query,
        inserted_at: {:placeholder, :datetime},
        updated_at: {:placeholder, :datetime2}
      ]

      # Row 2
      int2 = 2
      uuid2 = Ecto.UUID.generate()
      int_query = from l in Logging, where: l.int == ^int2 and l.uuid == ^uuid2, select: l.int

      row2 = [
        int: int_query,
        uuid: uuid2,
        inserted_at: {:placeholder, :datetime},
        updated_at: {:placeholder, :datetime2}
      ]

      # Placeholders
      datetime = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      datetime2 = NaiveDateTime.add(datetime, 1)
      placeholder_map = %{datetime: datetime, datetime2: datetime2}

      # Conflict query
      conflict_int = 0
      conflict_uuid = Ecto.UUID.generate()
      conflict_update = 2

      conflict_query =
        from l in Logging,
          where: l.int == ^conflict_int and l.uuid == ^conflict_uuid,
          update: [set: [int: ^conflict_update]]

      # Extract the parameters from the log:
      # 1. Remove the colour codes
      # 2. Remove the log level
      # 3. Capture everything inside of the square brackets
      log =
        capture_log(fn ->
          TestRepo.insert_all(Logging, [row1, row2],
            placeholders: placeholder_map,
            on_conflict: conflict_query,
            conflict_target: :bid,
            log: :info
          )
        end)

      log = Regex.replace(~r/\e\[[0-9]+m/, log, "")
      log = Regex.replace(~r/\[info\]/, log, "")
      log = Regex.named_captures(~r/\[(?<params>.+)\]/, log)
      log_params = String.split(log["params"], ",")

      # Compute the expected parameters in the right order.
      # This involves recreating the headers in the same order
      # as `insert_all`. The placeholders come first, then the
      # user value, then the autogenerated id and then the conflict
      # params
      headers =
        row1
        |> Enum.reduce(%{}, fn {field, _}, headers -> Map.put(headers, field, true) end)
        |> Map.put(:bid, true)
        |> Map.drop([:inserted_at, :updated_at])
        |> Map.keys()

      row1_regex = [
        int: "#{int}",
        uuid: ["#{int}", uuid],
        bid: @uuid_regex
      ]

      row2_regex = [
        int: ["#{int2}", uuid2],
        uuid: uuid2,
        bid: @uuid_regex
      ]

      row_param_regex =
        Enum.flat_map([row1_regex, row2_regex], fn row ->
          Enum.flat_map(headers, fn field ->
            case Keyword.get(row, field) do
              row_params when is_list(row_params) -> row_params
              row_param -> [row_param]
            end
          end)
        end)

      placeholder_regex = [inspect(datetime), inspect(datetime2)]
      conflict_param_regex = ["#{conflict_update}", "#{conflict_int}", conflict_uuid]
      expected_param_regex = placeholder_regex ++ row_param_regex ++ conflict_param_regex

      assert length(log_params) == length(expected_param_regex)

      Enum.zip(log_params, expected_param_regex)
      |> Enum.each(fn {log, expected_regex} ->
        assert log =~ expected_regex
      end)
    end

    test "for insert" do
      # Insert values
      int = 1
      uuid = Ecto.UUID.generate()

      # Ensure parameters are complete and in correct order
      log =
        capture_log(fn ->
          TestRepo.insert!(%Logging{uuid: uuid, int: int},
            log: :info
          )
        end)

      param_regex =
        ~r/\[(?<int>.+), \"(?<uuid>.+)\", (?<inserted_at>.+), (?<updated_at>.+), \"(?<bid>.+)\"\]/

      param_logs = Regex.named_captures(param_regex, log)

      # User changes
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
      # Autogenerated changes
      assert param_logs["inserted_at"] =~ @naive_datetime_regex
      assert param_logs["updated_at"] =~ @naive_datetime_regex
      # Filters
      assert param_logs["bid"] =~ @uuid_regex
    end

    @tag :with_conflict_target
    test "for insert with conflict query" do
      # Insert values
      int = 1
      uuid = Ecto.UUID.generate()

      # Conflict query
      conflict_int = 0
      conflict_uuid = Ecto.UUID.generate()
      conflict_update = 2

      conflict_query =
        from l in Logging,
          where: l.int == ^conflict_int and l.uuid == ^conflict_uuid,
          update: [set: [int: ^conflict_update]]

      # Ensure parameters are complete and in correct order
      log =
        capture_log(fn ->
          TestRepo.insert!(%Logging{uuid: uuid, int: int},
            on_conflict: conflict_query,
            conflict_target: :bid,
            log: :info
          )
        end)

      param_regex =
        ~r/\[(?<int>.+), \"(?<uuid>.+)\", (?<inserted_at>.+), (?<updated_at>.+), \"(?<bid>.+)\", (?<conflict_update>.+), (?<conflict_int>.+), \"(?<conflict_uuid>.+)\"\]/

      param_logs = Regex.named_captures(param_regex, log)

      # User changes
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
      # Autogenerated changes
      assert param_logs["inserted_at"] =~ @naive_datetime_regex
      assert param_logs["updated_at"] =~ @naive_datetime_regex
      # Filters
      assert param_logs["bid"] =~ @uuid_regex
      # Conflict query parameters
      assert param_logs["conflict_update"] == Integer.to_string(conflict_update)
      assert param_logs["conflict_int"] == Integer.to_string(conflict_int)
      assert param_logs["conflict_uuid"] == conflict_uuid
    end

    test "for update" do
      # Update values
      int = 1
      uuid = Ecto.UUID.generate()
      current = TestRepo.insert!(%Logging{})

      # Ensure parameters are complete and in correct order
      log =
        capture_log(fn ->
          TestRepo.update!(Ecto.Changeset.change(current, %{uuid: uuid, int: int}), log: :info)
        end)

      param_regex = ~r/\[(?<int>.+), \"(?<uuid>.+)\", (?<updated_at>.+), \"(?<bid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      # User changes
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
      # Autogenerated changes
      assert param_logs["updated_at"] =~ @naive_datetime_regex
      # Filters
      assert param_logs["bid"] == current.bid
    end

    test "for delete" do
      current = TestRepo.insert!(%Logging{})

      # Ensure parameters are complete and in correct order
      log =
        capture_log(fn ->
          TestRepo.delete!(current, log: :info)
        end)

      param_regex = ~r/\[\"(?<bid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      # Filters
      assert param_logs["bid"] == current.bid
    end

    test "for queries" do
      int = 1
      uuid = Ecto.UUID.generate()

      # all
      log =
        capture_log(fn ->
          TestRepo.all(
            from(l in Logging,
              select: type(^"1", :integer),
              where: l.int == ^int and l.uuid == ^uuid
            ),
            log: :info
          )
        end)

      param_regex = ~r/\[(?<tagged_int>.+), (?<int>.+), \"(?<uuid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      assert param_logs["tagged_int"] == Integer.to_string(int)
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid

      # update_all
      update = 2

      log =
        capture_log(fn ->
          from(l in Logging,
            where: l.int == ^int and l.uuid == ^uuid,
            update: [set: [int: ^update]]
          )
          |> TestRepo.update_all([], log: :info)
        end)

      param_regex = ~r/\[(?<update>.+), (?<int>.+), \"(?<uuid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      assert param_logs["update"] == Integer.to_string(update)
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid

      # delete_all
      log =
        capture_log(fn ->
          TestRepo.delete_all(from(l in Logging, where: l.int == ^int and l.uuid == ^uuid),
            log: :info
          )
        end)

      param_regex = ~r/\[(?<int>.+), \"(?<uuid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
    end

    @tag :stream
    test "for queries with stream" do
      int = 1
      uuid = Ecto.UUID.generate()

      log =
        capture_log(fn ->
          stream =
            TestRepo.stream(from(l in Logging, where: l.int == ^int and l.uuid == ^uuid),
              log: :info
            )

          TestRepo.transaction(fn -> Enum.to_list(stream) end)
        end)

      param_regex = ~r/\[(?<int>.+), \"(?<uuid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
    end

    @tag :array_type
    test "for queries with array type" do
      uuid = Ecto.UUID.generate()
      uuid2 = Ecto.UUID.generate()

      log =
        capture_log(fn ->
          TestRepo.all(from(a in ArrayLogging, where: a.uuids == ^[uuid, uuid2]),
            log: :info
          )
        end)

      param_regex = ~r/\[(?<uuids>\[.+\])\]/
      param_logs = Regex.named_captures(param_regex, log)

      assert param_logs["uuids"] == "[\"#{uuid}\", \"#{uuid2}\"]"
    end
  end
end
