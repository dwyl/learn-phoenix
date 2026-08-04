defmodule Mix.Tasks.Gettext.Merge do
  use Mix.Task
  @recursive true

  @shortdoc "Merge template files into message files"

  @moduledoc """
  Merges PO/POT files with PO files.

  This task is used when messages in the source code change: when they do,
  `mix gettext.extract` is usually used to extract the new messages to POT
  files. At this point, developers or translators can use this task to "sync"
  the newly-updated POT files with the existing locale-specific PO files. All
  the metadata for each message (like position in the source code, comments,
  and so on) is taken from the newly-updated POT file; the only things taken
  from the PO file are the actual translated strings.

  #### Fuzzy Matching

  Messages in the updated PO/POT file that have an exact match (a
  message with the same `msgid`) in the old PO file are merged as described
  above. When a message in the updated PO/POT files has no match in the old
  PO file, Gettext attemps a **fuzzy match** for that message. For example, imagine
  we have this POT file:

      msgid "hello, world!"
      msgstr ""

  and we merge it with this PO file:

      # No exclamation point here in the msgid
      msgid "hello, world"
      msgstr "ciao, mondo"

  Since the two messages are similar, Gettext takes the `msgstr` from the
  existing message over to the new message, which it however
  marks as *fuzzy*:

      #, fuzzy
      msgid "hello, world!"
      msgstr "ciao, mondo"

  Generally, a `fuzzy` flag calls for review from a translator.

  Fuzzy matching can be configured (for example, the threshold for message
  similarity can be tweaked) or disabled entirely. Look at the
  ["Options" section](#module-options).

  ## Usage

  ```bash
  mix gettext.merge OLD_FILE UPDATED_FILE [OPTIONS]
  mix gettext.merge DIR [OPTIONS]
  ```

  If two files are given as arguments, `OLD_FILE` must be a `.po` file and
  `UPDATE_FILE` must be a `.po`/`.pot` file. The first one is the old PO file,
  while the second one is the last generated one. They are merged and written
  over the first file. For example:

  ```bash
  mix gettext.merge priv/gettext/en/LC_MESSAGES/default.po priv/gettext/default.pot
  ```

  If only one argument is given, then that argument must be a directory
  containing Gettext messages (with `.pot` files at the root level alongside
  locale directories - this is usually a "backend" directory used by a Gettext
  backend, see `Gettext.Backend`). For example:

  ```bash
  mix gettext.merge priv/gettext
  ```

  If the `--locale LOCALE` option is given, then only the PO files in
  `<DIR>/<LOCALE>/LC_MESSAGES` will be merged with the POT files in `DIR`. If no
  options are given, then all the PO files for all locales under `DIR` are
  merged with the POT files in `DIR`.

  ## Plural Forms

  By default, Gettext will determine the number of plural forms for newly-generated messages
  by checking the value of `nplurals` in the `Plural-Forms` header in the existing `.po` file. If
  a `.po` file doesn't already exist and Gettext is creating a new one or if the `Plural-Forms`
  header is not in the `.po` file, Gettext will use the number of plural forms that
  the plural module (see `Gettext.Plural`) returns for the locale of the file being created.
  The content of the `Plural-Forms` header can be forced through the `--plural-forms-header`
  option (see below).

  ## Options

    * `--locale` - a string representing a locale. If this is provided, then only the PO
      files in `<DIR>/<LOCALE>/LC_MESSAGES` will be merged with the POT files in `DIR`. This
      option can only be given when a single argument is passed to the task
      (a directory).

    * `--no-fuzzy` - don't perform fuzzy matching when merging files.

    * `--fuzzy-threshold` - a float between `0` and `1` which represents the
      minimum Jaro distance needed for two messages to be considered a fuzzy
      match. Overrides the global `:fuzzy_threshold` option (see the docs for
      `Gettext` for more information on this option).

    * `--plural-forms` - (**deprecated in v0.22.0**) an integer strictly greater than `0`.
      If this is passed, new messages in the target PO files will have this number of empty
      plural forms. This is deprecated in favor of passing the `--plural-forms-header`,
      which contains the whole plural-forms specification. See the "Plural forms" section above.

    * `--plural-forms-header` - the content of the `Plural-Forms` header as a string.
      If this is passed, new messages in the target PO files will use this content
      to determine the number of plurals. See the ["Plural Forms" section](#module-plural-forms).

    * `--on-obsolete` - controls what happens when **obsolete** messages are found.
      If `mark_as_obsolete`, messages are kept and marked as obsolete.
      If `delete`, obsolete messages are deleted. Defaults to `delete`.

    * `--store-previous-message-on-fuzzy-match` - controls if the previous
      messages are recorded on fuzzy matches. Is off by default.

  """

  alias Expo.PO
  alias Gettext.Merger

  @default_fuzzy_threshold 0.8

  @switches [
    locale: :string,
    fuzzy: :boolean,
    fuzzy_threshold: :float,
    plural_forms_header: :string,
    on_obsolete: :string,
    store_previous_message_on_fuzzy_match: :boolean
  ]

  @impl true
  def run(args) do
    Mix.Task.run("loadpaths")

    _ = Mix.Project.get!()
    gettext_config = Mix.Project.config()[:gettext] || []

    case OptionParser.parse!(args, switches: @switches) do
      {opts, [po_file, reference_file]} ->
        merge_two_files(po_file, reference_file, opts, gettext_config)

      {opts, [messages_dir]} ->
        merge_messages_dir(messages_dir, opts, gettext_config)

      {_opts, _args} ->
        Mix.raise(
          "You can only pass one or two arguments to the \"gettext.merge\" task. " <>
            "Use `mix help gettext.merge` to see the usage of this task"
        )
    end

    Mix.Task.reenable("gettext.merge")
  end

  defp merge_two_files(po_file, reference_file, opts, gettext_config) do
    merging_opts = validate_merging_opts!(opts, gettext_config)

    if Path.extname(po_file) == ".po" and Path.extname(reference_file) in [".po", ".pot"] do
      ensure_file_exists!(po_file)
      ensure_file_exists!(reference_file)
      locale = locale_from_path(po_file)

      {contents, stats} =
        merge_files(po_file, reference_file, locale, merging_opts, gettext_config)

      write_file(po_file, contents, stats)
    else
      Mix.raise("Arguments must be a PO file and a PO/POT file")
    end
  end

  defp merge_messages_dir(dir, opts, gettext_config) do
    ensure_dir_exists!(dir)
    merging_opts = validate_merging_opts!(opts, gettext_config)

    if locale = opts[:locale] do
      merge_locale_dir(dir, locale, merging_opts, gettext_config)
    else
      merge_all_locale_dirs(dir, merging_opts, gettext_config)
    end
  end

  defp merge_locale_dir(pot_dir, locale, opts, gettext_config) do
    locale_dir = locale_dir(pot_dir, locale)
    create_missing_locale_dir(locale_dir)
    merge_dirs(locale_dir, pot_dir, locale, opts, gettext_config)
  end

  defp merge_all_locale_dirs(pot_dir, opts, gettext_config) do
    for locale <- File.ls!(pot_dir), File.dir?(Path.join(pot_dir, locale)) do
      merge_dirs(locale_dir(pot_dir, locale), pot_dir, locale, opts, gettext_config)
    end
  end

  def locale_dir(pot_dir, locale) do
    Path.join([pot_dir, locale, "LC_MESSAGES"])
  end

  defp merge_dirs(po_dir, pot_dir, locale, opts, gettext_config) do
    merger = fn pot_file ->
      po_file = find_matching_po(pot_file, po_dir)
      {contents, stats} = merge_or_create(pot_file, po_file, locale, opts, gettext_config)
      write_file(po_file, contents, stats)
    end

    pot_dir
    |> Path.join("*.pot")
    |> Path.wildcard()
    |> Task.async_stream(merger, ordered: false, timeout: :infinity)
    |> Stream.run()

    warn_for_po_without_pot(po_dir, pot_dir)
  end

  defp find_matching_po(pot_file, po_dir) do
    domain = Path.basename(pot_file, ".pot")
    Path.join(po_dir, "#{domain}.po")
  end

  defp merge_or_create(pot_file, po_file, locale, opts, gettext_config) do
    if File.regular?(po_file) do
      merge_files(po_file, pot_file, locale, opts, gettext_config)
    else
      {new_po, stats} = Merger.new_po_file(po_file, pot_file, locale, opts)

      {new_po
       |> Merger.prune_references(gettext_config)
       |> PO.compose(), stats}
    end
  end

  defp merge_files(po_file, pot_file, locale, opts, gettext_config) do
    {merged, stats} =
      Merger.merge(
        PO.parse_file!(po_file),
        PO.parse_file!(pot_file),
        locale,
        opts,
        gettext_config
      )

    {merged
     |> Merger.prune_references(gettext_config)
     |> PO.compose(), stats}
  end

  defp write_file(path, contents, stats) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
    Mix.shell().info("Wrote #{path} (#{format_stats(stats)})")
  end

  # Warns for every PO file that has no matching POT file.
  defp warn_for_po_without_pot(po_dir, pot_dir) do
    po_dir
    |> Path.join("*.po")
    |> Path.wildcard()
    |> Enum.reject(&po_has_matching_pot?(&1, pot_dir))
    |> Enum.each(fn po_file ->
      Mix.shell().info("Warning: PO file #{po_file} has no matching POT file in #{pot_dir}")
    end)
  end

  defp po_has_matching_pot?(po_file, pot_dir) do
    domain = Path.basename(po_file, ".po")
    pot_path = Path.join(pot_dir, "#{domain}.pot")
    File.exists?(pot_path)
  end

  defp ensure_file_exists!(path) do
    unless File.regular?(path), do: Mix.raise("No such file: #{path}")
  end

  defp ensure_dir_exists!(path) do
    unless File.dir?(path), do: Mix.raise("No such directory: #{path}")
  end

  defp create_missing_locale_dir(dir) do
    unless File.dir?(dir) do
      File.mkdir_p!(dir)
      Mix.shell().info("Created directory #{dir}")
    end
  end

  defp validate_merging_opts!(opts, gettext_config) do
    opts =
      opts
      |> Keyword.take([
        :fuzzy,
        :fuzzy_threshold,
        :plural_forms_header,
        :on_obsolete,
        :store_previous_message_on_fuzzy_match
      ])
      |> Keyword.put_new(:store_previous_message_on_fuzzy_match, false)
      |> Keyword.put_new(:fuzzy, true)
      |> Keyword.put_new_lazy(:fuzzy_threshold, fn ->
        gettext_config[:fuzzy_threshold] || @default_fuzzy_threshold
      end)
      |> Keyword.update(:on_obsolete, :delete, &cast_on_obsolete/1)

    threshold = opts[:fuzzy_threshold]

    unless threshold >= 0.0 and threshold <= 1.0 do
      Mix.raise("The :fuzzy_threshold option must be a float >= 0.0 and <= 1.0")
    end

    opts
  end

  defp locale_from_path(path) do
    parts = Path.split(path)
    index = Enum.find_index(parts, &(&1 == "LC_MESSAGES"))
    Enum.at(parts, index - 1)
  end

  defp format_stats(stats) do
    pluralized = if stats.new == 1, do: "message", else: "messages"

    "#{stats.new} new #{pluralized}, #{stats.removed} removed, " <>
      "#{stats.exact_matches} unchanged, #{stats.fuzzy_matches} reworded (fuzzy), " <>
      "#{stats.marked_as_obsolete} marked as obsolete"
  end

  defp cast_on_obsolete("delete" = _on_obsolete), do: :delete
  defp cast_on_obsolete("mark_as_obsolete" = _on_obsolete), do: :mark_as_obsolete

  defp cast_on_obsolete(on_obsolete) do
    Mix.raise("""
    An invalid value was provided for the option `on_obsolete`.
    Value: #{inspect(on_obsolete)}
    Valid Choices: "delete" / "mark_as_obsolete"
    """)
  end
end
