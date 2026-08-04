defmodule NimblePool.Application do
  @moduledoc false
  use Application

  def start(_type, _opts) do
    children = [
      {Task.Supervisor, name: NimblePool.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
