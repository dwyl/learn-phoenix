# LazyHTML

[![Docs](https://img.shields.io/badge/hex.pm-docs-8e7ce6.svg)](https://hexdocs.pm/lazy_html)
[![Actions Status](https://github.com/dashbitco/lazy_html/workflows/Test/badge.svg)](https://github.com/dashbitco/lazy_html/actions)

<!-- Docs -->

Efficient parsing and querying of HTML documents.

LazyHTML is designed around lazy HTML documents. Documents are parsed
and kept natively in memory for as long as possible. Query selectors
are executed in native code for performance and adheres to browser standards.
Under the hood, LazyHTML uses [Lexbor](https://github.com/lexbor/lexbor),
a fast, dependency-free and comprehensive HTML engine, written entirely in C.

LazyHTML works with a flat list of nodes and all operations are batched
by default, as shown below:

```elixir
lazy_html =
  LazyHTML.from_fragment("""
  <div>
    <a href="https://elixir-lang.org">Elixir</a>
    <a href="https://www.erlang.org">Erlang</a>
  </div>\
  """)
#=> #LazyHTML<
#=>   1 node
#=>
#=>   #1
#=>   <div>
#=>     <a href="https://elixir-lang.org">Elixir</a>
#=>     <a href="https://www.erlang.org">Erlang</a>
#=>   </div>
#=> >

hyperlinks = LazyHTML.query(lazy_html, "a")
#=> #LazyHTML<
#=>   2 nodes (from selector)
#=>
#=>   #1
#=>   <a href="https://elixir-lang.org">Elixir</a>
#=>
#=>   #2
#=>   <a href="https://www.erlang.org">Erlang</a>
#=> >

LazyHTML.attribute(hyperlinks, "href")
#=> ["https://elixir-lang.org", "https://www.erlang.org"]
```

LazyHTML also provides several high-level conveniences:

- an `Inspect` implementation to pretty-print nodes
- an `Access` implementation to run CSS selectors
- an `Enumerable` implementation to traverse them

For example:

```elixir
lazy_html = LazyHTML.from_fragment(~S|<p><strong>Hello</strong>, <em>world</em>!</p>|)
#=> #LazyHTML<
#=>   1 node
#=>
#=>   #1
#=>   <p><strong>Hello</strong>, <em>world</em>!</p>
#=> >

lazy_html["strong, em"]
#=> #LazyHTML<
#=>   2 nodes (from selector)
#=>
#=>   #1
#=>   <strong>Hello</strong>
#=>
#=>   #2
#=>   <em>world</em>
#=> >

LazyHTML.text(lazy_html)
#=> "Hello, world!"

Enum.map(lazy_html["strong, em"], &LazyHTML.text/1)
#=> ["Hello", "world"]
```

If needed, the lazy nodes can be converted into an Elixir tree data
structure, and vice-versa.

```elixir
lazy_html = LazyHTML.from_fragment("<p><strong>Hello</strong>, <em>world</em>!</p>")
#=> #LazyHTML<
#=>   1 node
#=>
#=>   #1
#=>   <p><strong>Hello</strong>, <em>world</em>!</p>
#=> >

tree = LazyHTML.to_tree(lazy_html)
#=> [{"p", [], [{"strong", [], ["Hello"]}, ", ", {"em", [], ["world"]}, "!"]}]

LazyHTML.from_tree(tree)
#=> #LazyHTML<
#=>   1 node

#=>   #1
#=>   <p><strong>Hello</strong>, <em>world</em>!</p>
#=> >
```

<!-- Docs -->

## License

    Copyright (c) 2025 Dashbit

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
