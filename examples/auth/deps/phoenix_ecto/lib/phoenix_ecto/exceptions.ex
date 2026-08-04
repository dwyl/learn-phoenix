defmodule Phoenix.Ecto.StorageNotCreatedError do
  defexception [:repo]

  def message(%__MODULE__{repo: repo}) do
    "the storage is not created for repo: #{inspect(repo)}. " <>
      "Try running `mix ecto.create` in the command line to create it"
  end
end

defmodule Phoenix.Ecto.PendingMigrationError do
  @enforce_keys [:repo, :directories, :migration_opts]
  defexception [:repo, :directories, :migration_opts]

  def message(%__MODULE__{repo: repo}) do
    "there are pending migrations for repo: #{inspect(repo)}. " <>
      "Try running `mix ecto.migrate` in the command line to migrate it"
  end
end
