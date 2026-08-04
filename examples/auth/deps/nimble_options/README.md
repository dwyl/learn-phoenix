# NimbleOptions

[![hex.pm badge](https://img.shields.io/badge/Package%20on%20hex.pm-informational)](https://hex.pm/packages/nimble_options)
[![Documentation badge](https://img.shields.io/badge/Documentation-ff69b4)][docs]
[![CI](https://github.com/dashbitco/nimble_options/actions/workflows/main.yml/badge.svg)](https://github.com/dashbitco/nimble_options/actions/workflows/main.yml)
[![Coverage Status](https://coveralls.io/repos/github/dashbitco/nimble_options/badge.svg?branch=master)](https://coveralls.io/github/dashbitco/nimble_options?branch=master)

[Online Documentation][docs].

A tiny library for validating and documenting high-level options.

This library allows you to validate options based on a definition.
A definition is a keyword list specifying how the options you want
to validate should look like:

```elixir
definition = [
  connections: [
    type: :non_neg_integer,
    default: 5
  ],
  url: [
    type: :string,
    required: true
  ]
]
```

Now you can validate options through `NimbleOptions.validate/2`:

```elixir
options = [url: "https://example.com"]

NimbleOptions.validate(options, definition)
#=> {:ok, [url: "https://example.com", connections: 5]}
```

If the options don't match the definition, an error is returned:

```elixir
NimbleOptions.validate([connections: 3], definition)
{:error,
 %NimbleOptions.ValidationError{
   keys_path: [],
   message: "required option :url not found, received options: [:connections]"
 }}
```

`NimbleOptions` is also capable of automatically generating
documentation for a definition by calling `NimbleOptions.docs/1`
with your definition.

## Installation

You can install `nimble_options` by adding it to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nimble_options, "~> 1.0"}
  ]
end
```

## Nimble*

All nimble libraries by Dashbit:

  * [NimbleCSV](https://github.com/dashbitco/nimble_csv) - simple and fast CSV parsing
  * [NimbleOptions](https://github.com/dashbitco/nimble_options) - tiny library for validating and documenting high-level options
  * [NimbleParsec](https://github.com/dashbitco/nimble_parsec) - simple and fast parser combinators
  * [NimblePool](https://github.com/dashbitco/nimble_pool) - tiny resource-pool implementation
  * [NimblePublisher](https://github.com/dashbitco/nimble_publisher) - a minimal filesystem-based publishing engine with Markdown support and code highlighting
  * [NimbleTOTP](https://github.com/dashbitco/nimble_totp) - tiny library for generating time-based one time passwords (TOTP)

## License

Copyright 2020 Dashbit

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

  > https://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

[docs]: https://hexdocs.pm/nimble_options
