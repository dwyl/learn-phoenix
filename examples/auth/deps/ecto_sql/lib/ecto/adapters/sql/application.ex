defmodule Ecto.Adapters.SQL.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Ecto.MigratorSupervisor},
      {Task.Supervisor, name: Ecto.Adapters.SQL.StorageSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Ecto.Adapters.SQL.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
