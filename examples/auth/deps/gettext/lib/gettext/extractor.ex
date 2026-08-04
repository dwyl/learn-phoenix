defmodule Gettext.Extractor do
  @moduledoc false

  # This module is responsible for extracting messages (it's called from the
  # *gettext macros) and dumping those messages to POT files, merging with
  # existing POT files if necessary.
  #
  # ## Ordering
  #
  # Ordering is mostly taken care of in merge_template/2, where we go over the
  # messages in an existing POT file and merge them if necessary (thus
  # keeping the order from the original file), then adding the messages from
  # the new in-memory POT (sorted by name).

  alias Gettext.Error
  alias Gettext.ExtractorAgent
  alias Gettext.Merger
  alias Expo.PO
  alias Expo.Message
  alias Expo.Messages

  @extracted_messages_flag "elixir-autogen"

  @new_pot_comment String.split(
                     """
                     # This file is a PO Template file.
                     #
                     # "msgid"s here are often extracted from source code.
                     # Add new messages manually only if they're dynamic
                     # messages that can't be statically extracted.
                     #
                     # Run "mix gettext.extract" to bring this file up to
                     # date. Leave "msgstr"s empty as changing them here has no
                     # effect: edit them in PO (.po) files instead.
                     """,
                     "\n"
                   )

  @doc """
  Enables message extraction.
  """
  @spec enable() :: :ok
  def enable() do
    ExtractorAgent.enable()
  end

  @doc """
  Disables extraction.
  """
  @spec disable() :: :ok
  def disable() do
    ExtractorAgent.disable()
  end

  @doc """
  Tells whether messages are being extracted.
  """
  @spec extracting?() :: boolean
  def extracting?() do
    # Because the extractor agent may not be enabled during compilation
    # time (as it requires the optional Gettext compiler), we need to
    # check if the agent is up and running before querying it.
    Process.whereis(ExtractorAgent) && ExtractorAgent.extracting?()
  end

  @doc """
  Extracts a message by temporarily storing it in an agent.

  Note that this function doesn't perform any operation on the filesystem.
  """
  @spec extract(
          Macro.Env.t(),
          backend :: module,
          domain :: binary | :default,
          msgctxt :: binary,
          id :: binary | {binary, binary},
          extracted_comments :: [binary]
        ) :: :ok
  def extract(%Macro.Env{} = caller, backend, domain, msgctxt, id, extracted_comments) do
    format_flag = backend.__gettext__(:interpolation).message_format()

    domain =
      case domain do
        :default -> backend.__gettext__(:default_domain)
        string when is_binary(string) -> string
      end

    message =
      create_message_struct(
        id,
        msgctxt,
        caller.file,
        caller.line,
        extracted_comments,
        format_flag
      )

    ExtractorAgent.add_message(backend, domain, message)
  end

  @doc """
  Returns a list of POT files based on the results of the extraction.

  Returns a list of paths and their contents to be written to disk. Existing POT
  files are either purged from obsolete messages (in case no extracted
  message ends up in that file) or merged with the extracted messages;
  new POT files are returned for extracted messages that belong to a POT
  file that doesn't exist yet.

  This is a stateful operation. Once pot_files are generated, their information
  is permanently removed from the extractor.
  """
  @spec pot_files(atom, Keyword.t()) :: [{path :: String.t(), contents :: iodata}]
  def pot_files(app, gettext_config) do
    backends = ExtractorAgent.pop_backends(app)
    warn_on_conflicting_backends(backends)
    existing_pot_files = pot_files_for_backends(backends)

    backends
    |> ExtractorAgent.pop_message()
    |> create_po_structs_from_extracted_messages()
    |> merge_pot_files(existing_pot_files, gettext_config)
  end

  defp warn_on_conflicting_backends(backends) do
    Enum.reduce(backends, %{}, fn backend, acc ->
      priv = backend.__gettext__(:priv)

      case acc do
        %{^priv => other_backend} ->
          IO.warn(
            "the Gettext backend #{inspect(backend)} has the same :priv directory as " <>
              "#{inspect(other_backend)}, which means they will override each other. " <>
              "Please set the :priv option to different directories or use Gettext " <>
              "inside each backend"
          )

          acc

        %{} ->
          Map.put(acc, priv, backend)
      end
    end)
  end

  # Returns all the .pot files for each of the given `backends`.
  defp pot_files_for_backends(backends) do
    Enum.flat_map(backends, fn backend ->
      backend.__gettext__(:priv)
      |> Path.join("**/*.pot")
      |> Path.wildcard()
    end)
  end

  # This returns a list of {absolute_path, %Gettext.PO{}} tuples.
  # `all_messages` looks like this:
  #
  #     %{MyBackend => %{"a_domain" => %{"a message id" => a_message}}}
  #
  defp create_po_structs_from_extracted_messages(all_messages) do
    for {backend, domains} <- all_messages,
        {domain, messages} <- domains do
      messages = Map.values(messages)
      {pot_path(backend, domain), po_struct_from_messages(messages)}
    end
  end

  defp pot_path(backend, domain) do
    Path.join(backend.__gettext__(:priv), "#{domain}.pot")
  end

  defp po_struct_from_messages(messages) do
    # Sort all the messages and the references of each message in order
    # to make as few changes as possible to the PO(T) files.
    messages =
      messages
      |> Enum.sort_by(&Message.key/1)
      |> Enum.map(&sort_references/1)

    %Messages{messages: messages, top_comments: @new_pot_comment, headers: [""]}
  end

  defp sort_references(message) do
    update_in(message.references, &Enum.sort/1)
  end

  defp create_message_struct(
         {msgid, msgid_plural},
         msgctxt,
         file,
         line,
         extracted_comments,
         format_flag
       ) do
    %Message.Plural{
      msgid: [msgid],
      msgctxt: if(msgctxt != nil, do: [msgctxt], else: nil),
      msgid_plural: [msgid_plural],
      msgstr: %{0 => [""], 1 => [""]},
      flags: [[@extracted_messages_flag, format_flag]],
      references: [[{Path.relative_to_cwd(file), line}]],
      extracted_comments: extracted_comments
    }
  end

  defp create_message_struct(msgid, msgctxt, file, line, extracted_comments, format_flag) do
    %Message.Singular{
      msgid: [msgid],
      msgctxt: if(msgctxt != nil, do: [msgctxt], else: nil),
      msgstr: [""],
      flags: [[@extracted_messages_flag, format_flag]],
      references: [[{Path.relative_to_cwd(file), line}]],
      extracted_comments: extracted_comments
    }
  end

  # Made public for testing.
  @doc false
  def merge_pot_files(po_structs, pot_files, gettext_config) do
    # pot_files is a list of paths to existing .pot files while po_structs is a
    # list of {path, struct} for new %Gettext.PO{} structs that we have
    # extracted. If we turn pot_files into a list of {path, whatever} tuples,
    # then we can take advantage of Map.merge/3 to find files that we have to
    # update, delete, or add.
    pot_files = Map.new(pot_files, &{&1, :existing})

    po_structs =
      Map.new(po_structs, fn {path, struct} ->
        {path, Merger.prune_references(struct, gettext_config)}
      end)

    # After Map.merge/3, we have something like:
    #   %{path => {:merged, :unchanged | %Messages{}}, path => %Messages{}, path => :existing}
    # and after mapping tag_files/1 over that we have something like:
    #   %{path => {:merged, :unchanged | %Messages{}}, path => {:unmerged, :unchanged | %Messages{}}, path => {:new, %Messages{}}}
    Map.merge(pot_files, po_structs, &merge_existing_and_extracted(&1, &2, &3, gettext_config))
    |> Enum.map(&tag_files(&1, gettext_config))
    |> Enum.map(&dump_tagged_file/1)
  end

  # This function is called by merge_pot_files/2 as the function passed to
  # Map.merge/3 (so when we have both an :existing file and a new extracted
  # in-memory PO struct both located at "path").
  defp merge_existing_and_extracted(path, :existing, extracted, gettext_config) do
    {:merged, merge_or_unchanged(path, extracted, gettext_config)}
  end

  # Returns :unchanged if merging `existing_path` with `new_po` changes nothing,
  # otherwise a %Gettext.PO{} struct with the changed contents.
  defp merge_or_unchanged(existing_path, new_po, gettext_config) do
    {existing_contents, existing_po} = read_contents_and_parse(existing_path)
    merged_po = merge_template(existing_po, new_po, gettext_config)

    if IO.iodata_to_binary(PO.compose(merged_po)) == existing_contents do
      :unchanged
    else
      merged_po
    end
  end

  defp read_contents_and_parse(path) do
    contents = File.read!(path)
    {contents, PO.parse_file!(path, file: path)}
  end

  # This function "tags" a {path, _} tuple in order to distinguish POT files
  # that have been merged (one existed at `path` and there's a new one to put at
  # `path` as well), POT files that exist but have no new counterpart (`{path,
  # :existing}`) and new files that do not exist yet.
  # These are marked as:
  #   * {path, {:merged, _}} - one existed and there's a new one
  #   * {path, {:unmerged, _}} - one existed, no new one
  #   * {path, {:new, _}} - none existed, there's a new one
  # Note that existing files with no new corresponding file are "pruned", for example,
  # merged with an empty %Messages{} struct to remove obsolete message (see
  # prune_unmerged/1), because the user could still have PO message that
  # they manually inserted in that file.
  defp tag_files({_path, {:merged, _}} = entry, _gettext_config), do: entry

  defp tag_files({path, :existing}, gettext_config),
    do: {path, {:unmerged, prune_unmerged(path, gettext_config)}}

  defp tag_files({path, new_po}, _gettext_config), do: {path, {:new, new_po}}

  # This function "dumps" merged files and unmerged files without any changes,
  # and dumps new POT files adding an informative comment to them. This doesn't
  # write anything to disk, it just returns `{path, contents}` tuples.
  defp dump_tagged_file({path, {_tag, :unchanged}}), do: {path, :unchanged}
  defp dump_tagged_file({path, {_tag, po}}), do: {path, {:changed, PO.compose(po)}}

  defp prune_unmerged(path, gettext_config) do
    merge_or_unchanged(path, %Messages{messages: []}, gettext_config)
  end

  # Merges a %Messages{} struct representing an existing POT file with an
  # in-memory-only %Messages{} struct representing the new POT file.
  # Made public for testing.
  @doc false
  def merge_template(existing, new, gettext_config) do
    protected_pattern = gettext_config[:excluded_refs_from_purging]

    # We go over the existing message in order so as to keep the existing
    # order as much as possible.
    old_and_merged =
      Enum.flat_map(existing.messages, fn message ->
        cond do
          same = Messages.find(new, message) -> [merge_message(message, same)]
          protected?(message, protected_pattern) -> [message]
          autogenerated?(message) -> []
          true -> [message]
        end
      end)

    # We reject all messages that appear in `existing` so that we're left
    # with the messages that only appear in `new`.
    unique_new = Enum.reject(new.messages, &Messages.find(existing, &1))

    messages = old_and_merged ++ unique_new

    sort_by_msgid =
      case gettext_config[:sort_by_msgid] || false do
        val when val in [:case_sensitive, :case_insensitive, false] ->
          val

        true ->
          IO.warn("""
          Passing "true" to the :sort_by_msgid option is deprecated. \
          Use :case_sensitive instead, or specify :case_insensitive.\
          """)

          :case_sensitive
      end

    messages =
      case sort_by_msgid do
        :case_sensitive ->
          Enum.sort_by(messages, &IO.chardata_to_string(&1.msgid))

        :case_insensitive ->
          Enum.sort_by(messages, &String.downcase(IO.chardata_to_string(&1.msgid)))

        false ->
          messages
      end

    %Messages{
      messages: messages,
      headers: existing.headers,
      top_comments: existing.top_comments
    }
  end

  defp merge_message(old, new) do
    ensure_empty_msgstr!(old)
    ensure_empty_msgstr!(new)

    # Take all flags from `old` and only the `@extracted_messages_flag` flag from `new`
    # to avoid re-adding manually removed flags.
    flags =
      if Message.has_flag?(new, @extracted_messages_flag) do
        Message.append_flag(old, @extracted_messages_flag).flags
      else
        old.flags
      end

    old
    |> Message.merge(new)
    |> Map.merge(%{
      flags: flags,
      # We don't care about the references of the old message since the new
      # in-memory message has all the actual and current references.
      references: new.references,
      extracted_comments: new.extracted_comments
    })
  end

  defp ensure_empty_msgstr!(%Message.Singular{msgstr: msgstr} = message) do
    unless blank?(msgstr) do
      raise Error,
            "message with msgid '#{IO.iodata_to_binary(message.msgid)}' has a non-empty msgstr"
    end
  end

  defp ensure_empty_msgstr!(%Message.Plural{msgstr: msgstr} = message) do
    if Enum.any?(Map.values(msgstr), &(not blank?(&1))) do
      raise Error,
            "plural message with msgid '#{IO.iodata_to_binary(message.msgid)}' has a non-empty msgstr"
    end
  end

  defp ensure_empty_msgstr!(%Message.Plural{} = message) do
    raise Error,
          "plural message with msgid '#{IO.iodata_to_binary(message.msgid)}' has a non-empty msgstr"
  end

  defp blank?(str) when not is_nil(str), do: IO.iodata_length(str) == 0
  defp blank?(_), do: true

  @spec autogenerated?(message :: Message.t()) :: boolean
  defp autogenerated?(message) do
    Message.has_flag?(message, "elixir-autogen")
  end

  # A message that is protected from purging will never be removed by Gettext.
  # Which messages are proteced can be configured using Mix.
  @spec protected?(message :: Message.t(), protected_pattern :: Regex.t()) :: boolean
  defp protected?(_t, nil),
    do: false

  defp protected?(%{references: []}, _pattern),
    do: false

  defp protected?(%{references: refs}, pattern),
    do: refs |> List.flatten() |> Enum.any?(fn {path, _} -> Regex.match?(pattern, path) end)
end
