defmodule Phoenix.Ecto do
  @moduledoc """
  Integrates Phoenix with Ecto.

  It implements many protocols that make it easier to use
  Ecto with Phoenix either when working with HTML or JSON.
  """
  use Application

  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: Phoenix.Ecto.SQL.SandboxSupervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Phoenix.Ecto.Supervisor)
  end
end
