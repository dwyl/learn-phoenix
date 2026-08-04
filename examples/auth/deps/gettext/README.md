# Gettext

[![hex.pm badge](https://img.shields.io/badge/Package%20on%20hex.pm-informational)](https://hex.pm/packages/gettext)
[![Documentation badge](https://img.shields.io/badge/Documentation-ff69b4)][docs-gettext]
![CI badge](https://github.com/elixir-gettext/gettext/workflows/CI/badge.svg)

Gettext is an **internationalization** (i18n) and **localization** (l10n) system commonly used for writing multilingual programs. Gettext is a standard for i18n in different communities, meaning there is a great set of tooling for developers and translators. This project is an implementation of the Gettext system in Elixir.

## Installation

Add `:gettext` to your list of dependencies in `mix.exs` (use `$ mix hex.info gettext` to find the latest version):

```elixir
defp deps do
  [
    {:gettext, ">= 0.0.0"}
  ]
end
```

Documentation for `Gettext` is [available on Hex][docs-gettext].

## Usage

To use Gettext, define a **Gettext backend**:

```elixir
defmodule MyApp.Gettext do
  use Gettext.Backend, otp_app: :my_app
end
```

and invoke the Gettext API, which consists of the `*gettext` macros that get imported if you `use Gettext`:

```elixir
use Gettext, backend: MyApp.Gettext

# Simple message
gettext("Here is one string to translate")

# Plural message
number_of_apples = 4
ngettext("The apple is ripe", "The apples are ripe", number_of_apples)

# Domain-based message
dgettext("errors", "Here is an error message to translate")
```

Messages in Gettext are stored in Portable Object files (`.po`). Such files must be placed at `priv/gettext/LOCALE/LC_MESSAGES/DOMAIN.po`, where `LOCALE` is the locale and `DOMAIN` is the domain (the default domain is called `default`).

For example, the message to `pt_BR` of the first two `*gettext` calls in the snippet above must be placed in the `priv/gettext/pt_BR/LC_MESSAGES/default.po` file with contents:

```pot
msgid "Here is one string to translate"
msgstr "Aqui está um texto para traduzir"

msgid "Here is the string to translate"
msgid_plural "Here are the strings to translate"
msgstr[0] "Aqui está o texto para traduzir"
msgstr[1] "Aqui estão os textos para traduzir"
```

`.po` are text-based files and can be edited directly by translators. Some may even use existing tools for managing them, such as [Poedit][poedit] or [poeditor.com][poeditor.com].

Finally, because messages are based on strings, your source code does not lose readability as you still see literal strings, like `gettext("here is an example")`, instead of paths like `translate("some.path.convention")`.

Read the [documentation for the `Gettext` module][docs-gettext-module] for more information on locales, interpolation, pluralization, and other features.

## Workflow

Gettext is able to automatically extract messages from your source code, alleviating developers and translators from the repetitive and error-prone work of maintaining message files.

When extracted from source, Gettext places messages into `.pot` files, which are template files. You can then merge those templates files into message files for each specific locale your application is being currently translated to.

In other words, the typical workflow looks like this:

  1. Add `gettext` calls to your source code. No need to touch message files
     at this point as Gettext will return the given string if no message is
     available:

     ```elixir
     gettext("Welcome back!")
     ```

  2. Once changes to the source are complete, automatically sync all existing entries to `.pot` (template files) in `priv/gettext` by running:

     ```bash
     mix gettext.extract
     ```

  3. You can then merge `.pot` files into locale-specific `.po` files:

     ```bash
     # Merge .pot into all locales
     mix gettext.merge priv/gettext

     # Merge .pot into one specific locale
     mix gettext.merge priv/gettext --locale en
     ```

It is also possible to both extract and merge messages in one step with `mix gettext.extract --merge`.

## License

Copyright 2015 Plataformatec
Copyright 2020 Dashbit

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at:

  > <http://www.apache.org/licenses/LICENSE-2.0>

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

[docs-gettext]: http://hexdocs.pm/gettext
[docs-gettext-module]: http://hexdocs.pm/gettext/Gettext.html
[poedit]: http://poedit.net/
[poeditor.com]: https://poeditor.com
