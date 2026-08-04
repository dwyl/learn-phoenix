errors = [
  {Ecto.CastError, 400},
  {Ecto.Query.CastError, 400},
  {Ecto.NoResultsError, 404},
  {Ecto.StaleEntryError, 409}
]

excluded_exceptions = Application.get_env(:phoenix_ecto, :exclude_ecto_exceptions_from_plug, [])

for {exception, status_code} <- errors do
  unless exception in excluded_exceptions do
    defimpl Plug.Exception, for: exception do
      def status(_), do: unquote(status_code)
      def actions(_), do: []
    end
  end
end

unless Ecto.SubQueryError in excluded_exceptions do
  defimpl Plug.Exception, for: Ecto.SubQueryError do
    def status(sub_query_error) do
      Plug.Exception.status(sub_query_error.exception)
    end

    def actions(_), do: []
  end
end

unless Phoenix.Ecto.PendingMigrationError in excluded_exceptions do
  defimpl Plug.Exception, for: Phoenix.Ecto.PendingMigrationError do
    def status(_error), do: 503

    def actions(%{repo: repo, directories: directories, migration_opts: migration_opts}),
      do: [
        %{
          label: "Run migrations for repo",
          handler: {__MODULE__, :migrate, [repo, directories, migration_opts]}
        }
      ]

    def migrate(repo, directories, migration_opts) do
      Ecto.Migrator.run(repo, directories, :up, Keyword.merge(migration_opts || [], all: true))
    end
  end
end

unless Phoenix.Ecto.StorageNotCreatedError in excluded_exceptions do
  defimpl Plug.Exception, for: Phoenix.Ecto.StorageNotCreatedError do
    def status(_error), do: 503

    def actions(%{repo: repo}),
      do: [
        %{
          label: "Create database for repo",
          handler: {__MODULE__, :storage_up, [repo]}
        }
      ]

    def storage_up(repo), do: repo.__adapter__().storage_up(repo.config())
  end
end

if Code.ensure_loaded?(Postgrex.Error) do
  unless Postgrex.Error in excluded_exceptions do
    defimpl Plug.Exception, for: Postgrex.Error do
      def status(%{postgres: %{code: :character_not_in_repertoire}}), do: 400
      def status(_), do: 500

      def actions(_), do: []
    end
  end
end
