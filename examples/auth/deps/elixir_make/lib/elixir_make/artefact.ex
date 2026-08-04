defmodule ElixirMake.Artefact do
  @moduledoc false

  require Logger
  alias ElixirMake.Artefact

  @checksum_algo :sha256
  defstruct [:basename, :checksum, :checksum_algo]

  @doc """
  Returns user cache directory.
  """
  def cache_dir() do
    cache_opts = if System.get_env("MIX_XDG"), do: %{os: :linux}, else: %{}

    cache_dir =
      Path.expand(
        System.get_env("ELIXIR_MAKE_CACHE_DIR") ||
          :filename.basedir(:user_cache, "elixir_make", cache_opts)
      )

    File.mkdir_p!(cache_dir)
    cache_dir
  end

  @doc """
  Returns the checksum algorithm
  """
  def checksum_algo do
    @checksum_algo
  end

  @doc """
  Computes the checksum and artefact for the given contents.
  """
  def checksum(basename, contents) do
    hash = :crypto.hash(checksum_algo(), contents)
    checksum = Base.encode16(hash, case: :lower)
    %Artefact{basename: basename, checksum: checksum, checksum_algo: checksum_algo()}
  end

  @doc """
  Writes checksum for the target to disk.
  """
  def write_checksum_for_target!(%Artefact{
        basename: basename,
        checksum: checksum,
        checksum_algo: checksum_algo
      }) do
    cache_dir = Artefact.cache_dir()
    file = Path.join(cache_dir, "#{basename}.#{Atom.to_string(checksum_algo)}")
    File.write!(file, [checksum, "  ", basename, "\n"])
  end

  @doc """
  Writes checksums to disk.
  """
  def write_checksums!(checksums) do
    file = checksum_file()

    pairs =
      Enum.map(checksums, fn
        %Artefact{basename: basename, checksum: checksum, checksum_algo: algo} ->
          {basename, "#{algo}:#{checksum}"}
      end)

    lines =
      for {filename, checksum} <- Enum.sort(pairs) do
        ~s(  "#{filename}" => "#{checksum}",\n)
      end

    File.write!(file, ["%{\n", lines, "}\n"])
  end

  defp checksum_file() do
    Path.join(File.cwd!(), "checksum.exs")
  end

  ## Archive handling

  @doc """
  Returns the full path to the precompiled archive.
  """
  def archive_path(config, target, nif_version) do
    Path.join(cache_dir(), archive_filename(config, target, nif_version))
  end

  defp archive_filename(config, target, nif_version) do
    case config[:make_precompiler] do
      {:nif, _} ->
        "#{config[:app]}-nif-#{nif_version}-#{target}-#{config[:version]}.tar.gz"

      {type, _} ->
        "#{config[:app]}-#{type}-#{target}-#{config[:version]}.tar.gz"
    end
  end

  @doc """
  Compresses the given files and computes its checksum and artefact.
  """
  def compress(archive_path, paths) do
    :ok = :erl_tar.create(archive_path, paths, [:compressed])
    checksum(Path.basename(archive_path), File.read!(archive_path))
  end

  @doc """
  Verifies and decompresses the given `archive_path` at `app_priv`.
  """
  def verify_and_decompress(archive_path, app_priv) do
    basename = Path.basename(archive_path)

    case File.read(archive_path) do
      {:ok, contents} ->
        verify_and_decompress(basename, archive_path, contents, app_priv)

      {:error, reason} ->
        {:error,
         "precompiled #{inspect(basename)} does not exist or cannot download: #{inspect(reason)}"}
    end
  end

  defp verify_and_decompress(basename, archive_path, contents, app_priv) do
    checksum_file()
    |> read_map_from_file()
    |> case do
      %{^basename => algo_with_checksum} ->
        [algo, checksum] = String.split(algo_with_checksum, ":")
        algo = String.to_existing_atom(algo)

        case checksum(basename, contents) do
          %Artefact{checksum: ^checksum, checksum_algo: ^algo} ->
            case :erl_tar.extract({:binary, contents}, [:compressed, {:cwd, app_priv}]) do
              :ok ->
                :ok

              {:error, term} ->
                {:error,
                 "cannot decompress precompiled #{inspect(archive_path)}: #{inspect(term)}"}
            end

          _ ->
            {:error, "precompiled #{inspect(basename)} does not match its checksum"}
        end

      checksum when checksum == %{} ->
        {:error, "missing checksum.exs file"}

      _checksum ->
        {:error, "precompiled #{inspect(basename)} does not exist in checksum.exs"}
    end
  end

  defp read_map_from_file(file) do
    with {:ok, contents} <- File.read(file),
         {%{} = contents, _} <- Code.eval_string(contents) do
      contents
    else
      _ -> %{}
    end
  end

  ## Archive/NIF urls

  defp nif_version_to_tuple(nif_version) do
    [major, minor | _] = String.split(nif_version, ".")
    {String.to_integer(major), String.to_integer(minor)}
  end

  defp fallback_version(opts) do
    current_nif_version = "#{:erlang.system_info(:nif_version)}"
    {major, minor} = nif_version_to_tuple(current_nif_version)

    # Get all matching major versions, earlier than the current version
    # and their distance. We want the closest (smallest distance).
    candidates =
      for version <- opts.versions,
          {^major, candidate_minor} <- [nif_version_to_tuple(version)],
          candidate_minor <= minor,
          do: {minor - candidate_minor, version}

    case Enum.sort(candidates) do
      [{_, version} | _] -> version
      _ -> current_nif_version
    end
  end

  defp get_versions_for_target(versions, current_target) do
    case versions do
      version_list when is_list(version_list) ->
        version_list

      version_func when is_function(version_func, 1) ->
        version_func.(%{target: current_target})
    end
  end

  @doc """
  Returns all available {{target, nif_version}, url} pairs available.
  """
  def available_target_urls(config, precompiler) do
    targets = precompiler.all_supported_targets(:fetch)

    url_template =
      config[:make_precompiler_url] ||
        Mix.raise("`make_precompiler_url` is not specified in `project`")

    current_nif_version = "#{:erlang.system_info(:nif_version)}"

    nif_versions =
      config[:make_precompiler_nif_versions] ||
        [versions: [current_nif_version]]

    Enum.reduce(targets, [], fn target, archives ->
      versions = get_versions_for_target(nif_versions[:versions], target)

      archive_filenames =
        Enum.reduce(versions, [], fn nif_version_for_target, acc ->
          availability = nif_versions[:availability]

          available? =
            if is_function(availability, 2) do
              IO.warn(
                ":availability key in elixir_make is deprecated, pass a function as :versions instead"
              )

              availability.(target, nif_version_for_target)
            else
              true
            end

          if available? do
            archive_filename = archive_filename(config, target, nif_version_for_target)

            [
              {{target, nif_version_for_target},
               String.replace(url_template, "@{artefact_filename}", archive_filename)}
              | acc
            ]
          else
            acc
          end
        end)

      archive_filenames ++ archives
    end)
  end

  @doc """
  Returns the url for the current target.
  """
  def current_target_url(config, precompiler, current_nif_version) do
    case precompiler.current_target() do
      {:ok, current_target} ->
        nif_versions =
          config[:make_precompiler_nif_versions] ||
            [versions: []]

        versions = get_versions_for_target(nif_versions[:versions], current_target)

        nif_version_to_use =
          if current_nif_version in versions do
            current_nif_version
          else
            fallback_version = nif_versions[:fallback_version] || (&fallback_version/1)
            opts = %{target: current_target, versions: versions}
            fallback_version.(opts)
          end

        available_urls = available_target_urls(config, precompiler)
        target_at_nif_version = {current_target, nif_version_to_use}

        case List.keyfind(available_urls, target_at_nif_version, 0) do
          {^target_at_nif_version, download_url} ->
            {:ok, current_target, nif_version_to_use, download_url}

          nil ->
            available_targets = Enum.map(available_urls, fn {target, _url} -> target end)

            {:error,
             {:unavailable_target, current_target,
              "cannot find download url for current target `#{inspect(current_target)}`. Available targets are: #{inspect(available_targets)}"}}
        end

      {:error, msg} ->
        {:error, msg}
    end
  end

  def download(config, url) do
    downloader = config[:make_precompiler_downloader] || ElixirMake.Downloader.Httpc
    downloader.download(url)
  end
end
