defmodule Rumbl.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      use Phoenix.ChannelTest

      alias Rumbl.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query


      # The default endpoint for testing
      @endpoint Rumbl.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Rumbl.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Rumbl.Repo, {:shared, self()})
    end

    :ok
  end
end
