Code.require_file "../../info_sys/test/backends/http_client.exs", __DIR__
ExUnit.start

# Mix.Task.run "ecto.create", ~w(-r Rumbl.Repo --quiet)
# Mix.Task.run "ecto.migrate", ~w(-r Rumbl.Repo --quiet)
# Ecto.Adapters.SQL.begin_test_transaction(Rumbl.Repo)

Ecto.Adapters.SQL.Sandbox.mode(Rumbl.Repo, :manual)
