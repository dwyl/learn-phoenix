# Fine

[![Docs](https://img.shields.io/badge/hex.pm-docs-8e7ce6.svg)](https://hexdocs.pm/fine)
[![Actions Status](https://github.com/elixir-nx/fine/workflows/CI/badge.svg)](https://github.com/elixir-nx/fine/actions)

<!-- Docs -->

Fine is a C++ library enabling more ergonomic NIFs, tailored to Elixir.

Erlang provides C API for implementing native functions
([`erl_nif`](https://www.erlang.org/doc/apps/erts/erl_nif.html)).
Fine is not a replacement of the C API, instead it is designed as a
complementary API, enhancing the developer experience when implementing
NIFs in C++.

## Features

- Automatic encoding/decoding of NIF arguments and return value,
  inferred from function signatures.

- Smart pointer enabling safe management of resource objects.

- Registering NIFs and resource types via simple annotations.

- Support for encoding/decoding Elixir structs based on compile time
  metadata.

- Propagating C++ exceptions as Elixir exceptions, with support for
  raising custom Elixir exceptions.

- Creating all static atoms at load time.

- STL compatible Erlang-backend mutex and rwlock.

- Compatible with STL container allocators and polymorphic memory
  resources.

## Motivation

Some projects make extensive use of NIFs, where using the C API results
in a lot of boilerplate code and a set of ad-hoc helper functions that
get copied from project to project. The main idea behind Fine is to
reduce the friction of getting from Elixir to C++ and vice versa, so
that developers can focus on writing the actual native code.

## Requirements

Currently Fine requires C++17. The supported compilers include GCC,
Clang and MSVC.

## Installation

Add `Fine` as a dependency in your `mix.exs`:

```elixir
def deps do
  [
    {:fine, "~> 0.1.0", runtime: false}
  ]
end
```

Modify your makefiles to look for Fine header files, similarly to the
ERTS ones. Also make sure to use at least C++17.

```shell
# GCC/Clang (Makefile)
CPPFLAGS += -I$(FINE_INCLUDE_DIR)
CPPFLAGS += -std=c++17

# MSVC (Makefile.win)
CPPFLAGS=$(CPPFLAGS) /I"$(FINE_INCLUDE_DIR)"
CPPFLAGS=$(CPPFLAGS) /std:c++17
```

When using `elixir_make`, set `FINE_INCLUDE_DIR` like this:

```elixir
def project do
  [
    ...,
    make_env: fn -> %{"FINE_INCLUDE_DIR" => Fine.include_dir()} end
  ]
end
```

Otherwise, you can inline the dir to `deps/fine/include`.

> #### Symbol visibility {: .info}
>
> When using GCC and Clang it is recommended to compile with
> `-fvisibility=hidden`. This flag hides symbols in your NIF shared
> library, which prevents from symbol clashes with other NIF libraries.
> This is required when multiple NIF libraries use Fine, otherwise
> loading the libraries fails.
>
> ```shell
> # GCC/Clang (Makefile)
> CPPFLAGS += -fvisibility=hidden
> ```

## Usage

A minimal NIF adding two numbers can be implemented like so:

```c++
#include <fine.hpp>

int64_t add(ErlNifEnv *env, int64_t x, int64_t y) {
  return x + y;
}

FINE_NIF(add, 0);

FINE_INIT("Elixir.MyLib.NIF");
```

See [`example/`](https://github.com/elixir-nx/fine/tree/main/example) project.

## Encoding/Decoding

Terms are automatically encoded and decoded at the NIF boundary based
on the function signature. In some cases, you may also want to invoke
encode/decode directly:

```c++
// Encode
auto message = std::string("hello world");
auto term = fine::encode(env, message);

// Decode
auto message = fine::decode<std::string>(env, term);
```

Fine provides implementations for the following types:

| C++ Type                             | Encoder | Decoder | Elixir Type                 |
| ------------------------------------ | ------- | ------- | --------------------------- |
| `fine::Term`                         | x       | x       | `term`                      |
| `int64_t`                            | x       | x       | `integer`                   |
| `uint64_t`                           | x       | x       | `non_neg_integer`           |
| `double`                             | x       | x       | `float`                     |
| `bool`                               | x       | x       | `boolean`                   |
| `ErlNifPid`                          | x       | x       | `pid`                       |
| `ErlNifBinary`                       | x       | x       | `binary`                    |
| `std::string_view`                   | x       | x       | `binary`                    |
| `std::string`                        | x       | x       | `binary`                    |
| `fine::Atom`                         | x       | x       | `atom`                      |
| `std::nullopt_t`                     | x       |         | `nil`                       |
| `std::optional<T>`                   | x       | x       | `a \| nil`                  |
| `std::variant<Args...>`              | x       | x       | `a \| b \| ... \| c`        |
| `std::tuple<Args...>`                | x       | x       | `{a, b, ..., c}`            |
| `std::vector<T>`                     | x       | x       | `list(a)`                   |
| `std::map<K, V>`                     | x       | x       | `%{k => v}`                 |
| `fine::ResourcePtr<T>`               | x       | x       | `reference`                 |
| `T` with [struct metadata](#structs) | x       | x       | `%a{}`                      |
| `fine::Ok<Args...>`                  | x       |         | `{:ok, ...}`                |
| `fine::Error<Args...>`               | x       |         | `{:error, ...}`             |

> #### ERL_NIF_TERM {: .warning}
>
> In some cases, you may want to define a NIF that accepts or returns
> a term and effectively skip the encoding/decoding. However, the NIF
> C API defines `ERL_NIF_TERM` as an alias for an integer type, which
> may introduce an ambiguity for encoding/decoding. For this reason
> Fine provides a wrapper type `fine::Term` and it should be used in
> the NIF signature in those cases. `fine::Term` defines implicit
> conversion to and from `ERL_NIF_TERM`, so it can be used with all
> `enif_*` functions with no changes.

> #### Binaries {: .info}
>
> `std::string` is just a sequence of `char`s and therefore it makes
> for a good counterpart for Elixir binaries, regardless if we are
> talking about UTF-8 encoded strings or arbitrary binaries.
>
> However, when dealing with large binaries, it is preferable for the
> NIF to accept `std::string_view` (or `ErlNifBinary`) as arguments and
> deal with the raw data explicitly, which is zero-copy. That said,
> keep in mind that those objects are read-only pointers to the data
> and they are valid only during the NIF call lifetime.
>
> Since Elixir binaries are not zero-terminated, the use of
> `std::string` is recommended when interfacing with C APIs, although
> this will require an additional allocation, which cannot be
> circumvented.
>
> Similarly, when returning large binaries, prefer creating the term
> with `fine::make_new_binary` and returning `fine::Term`, instead of
> allocating an intermediary `std::string`, as shown below.
>
> ```c++
> fine::Term read_data(ErlNifEnv *env) {
>   const char *buffer = ...;
>   uint64_t size = ...;
>
>   return fine::make_new_binary(env, buffer, size);
> }
> ```
>
> You can also return `std::string_view`, as long as the data it points
> to outlives the return.
>
> In case you return `ErlNifBinary` allocated with `enif_alloc_binary`,
> keep in mind that returning the binary converts it to term, which in
> turn transfers the ownership, so you should not use that `ErlNifBinary`
> after the NIF finishes.

You can extend encoding/decoding to work on custom types by defining
the following specializations:

```c++
// Note that the specialization must be defined in the `fine` namespace.
namespace fine {
  template <> struct Decoder<MyType> {
    static MyType decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
      // ...
    }
  };

  template <> struct Encoder<MyType> {
    static ERL_NIF_TERM encode(ErlNifEnv *env, const MyType &value) {
      // ...
    }
  };
}
```

## Resource objects

Resource objects is a mechanism for passing pointers to C++ data
structures to and from NIFs, and around your Elixir code. On the Elixir
side those pointer surface as reference terms (`#Reference<...>`).

Fine provides a construction function `fine::make_resource<T>(...)`,
similar to `std::make_unique` and `std::make_shared` available in the
C++ standard library. This function creates a new object of the type
`T`, invoking its constructor with the given arguments and it returns
a smart pointer of type `fine::ResourcePtr<T>`. The pointer is
automatically decoded and encoded as a reference term. It can also be
passed around C++ code, automatically managing the reference count
(similarly to `std::shared_ptr`).

You need to indicate that a given class can be used as a resource type
via the `FINE_RESOURCE` macro.

```c++
#include <fine.hpp>

class Generator {
public:
  Generator(uint64_t seed) { /* ... */ }
  int64_t random_integer() { /* ... */ }
  // ...
};

FINE_RESOURCE(Generator);

fine::ResourcePtr<Generator> create_generator(ErlNifEnv *env, uint64_t seed) {
  return fine::make_resource<Generator>(seed);
}

FINE_NIF(create_generator, 0);

int64_t random_integer(ErlNifEnv *env, fine::ResourcePtr<Generator> generator) {
  return generator->random_integer();
}

FINE_NIF(random_integer, 0);

FINE_INIT("Elixir.MyLib.NIF");
```

Once neither Elixir nor C++ holds a reference to the resource object,
it gets destroyed. By default only the `T` type destructor is called.
However, in some cases you may want to interact with NIF APIs as part
of the destructor. In that case, you can implement a `destructor`
callback on `T`, which receives the relevant `ErlNifEnv`:

```c++
class Generator {
  // ...

  void destructor(ErlNifEnv *env) {
    // Example: send a message to some process using env
  }
};
```

If defined, the `destructor` callback is called first, and then the
`T` destructor is called as usual.

Oftentimes NIFs deal with classes from third-party packages, in which
case, you may not control how the objects are created and you cannot
add callbacks such as `destructor` to the implementation. If you run
into any of these limitations, you can define your own wrapper class,
holding an object of the third-party class and implementing the desired
construction/destruction on top.

You can use `fine::make_resource_binary(env, resource, data, size)`
to create a binary term with memory managed by the resource.

## Structs

Elixir structs can be passed to and from NIFs. To do that, you need to
define a corresponding C++ class that includes metadata fields used
for automatic encoding and decoding. The metadata consists of:

- `module` - the Elixir struct name as an atom reference

- `fields` - a mapping between Elixir struct and C++ class fields

- `is_exception` (optional) - when defined as true, indicates the
  Elixir struct is an exception

For example, given an Elixir struct `%MyLib.Point{x: integer, y: integer}`,
you could operate on it in the NIF, like this:

```c++
#include <fine.hpp>

namespace atoms {
  auto ElixirMyLibPoint = fine::Atom("Elixir.MyLib.Point");
  auto x = fine::Atom("x");
  auto y = fine::Atom("y");
}

struct ExPoint {
  int64_t x;
  int64_t y;

  static constexpr auto module = &atoms::ElixirMyLibPoint;

  static constexpr auto fields() {
    return std::make_tuple(std::make_tuple(&ExPoint::x, &atoms::x),
                           std::make_tuple(&ExPoint::y, &atoms::y));
  }
};

ExPoint point_reflection(ErlNifEnv *env, ExPoint point) {
  return ExPoint{-point.x, -point.y};
}

FINE_NIF(point_reflection, 0);

FINE_INIT("Elixir.MyLib.NIF");
```

Structs can be particularly convenient when using NIF resource objects.
When working with resources, it is common to have an Elixir struct
corresponding to the resource. In the previous `Generator` example,
you may define an Elixir struct such as `%MyLib.Generator{resource: reference}`.
Instead of passing and returning the reference from the NIF, you can
pass and return the struct itself:

```c++
#include <fine.hpp>

class Generator {
public:
  Generator(uint64_t seed) { /* ... */ }
  int64_t random_integer() { /* ... */ }
  // ...
};

namespace atoms {
  auto ElixirMyLibGenerator = fine::Atom("Elixir.MyLib.Generator");
  auto resource = fine::Atom("resource");
}

struct ExGenerator {
  fine::ResourcePtr<Generator> resource;

  static constexpr auto module = &atoms::ElixirMyLibPoint;

  static constexpr auto fields() {
    return std::make_tuple(
      std::make_tuple(&ExGenerator::resource, &atoms::resource),
    );
  }
};

ExGenerator create_generator(ErlNifEnv *env, uint64_t seed) {
  return ExGenerator{fine::make_resource<Generator>(seed)};
}

FINE_NIF(create_generator, 0);

int64_t random_integer(ErlNifEnv *env, ExGenerator ex_generator) {
  return ex_generator.resource->random_integer();
}

FINE_NIF(random_integer, 0);

FINE_INIT("Elixir.MyLib.NIF");
```

## Exceptions

All C++ exceptions thrown within the NIF are caught and raised as
Elixir exceptions.

```c++
throw std::runtime_error("something went wrong");
// ** (RuntimeError) something went wrong

throw std::invalid_argument("expected x, got y");
// ** (ArgumentError) expected x, got y

throw OtherError(...);
// ** (RuntimeError) unknown exception thrown within NIF
```

Additionally, you can use `fine::raise(env, value)` to raise exception,
where `value` is encoded into a term and used as the exception. This
is not particularly useful with regular types, however it can be used
to raise custom Elixir exceptions. Consider the following exception:

```elixir
defmodule MyLib.MyError do
  defexception [:data]

  @impl true
  def message(error) do
    "got error with data #{error.data}"
  end
end
```

First, we need to implement the corresponding C++ class:

```c++
namespace atoms {
  auto ElixirMyLibMyError = fine::Atom("Elixir.MyLib.MyError");
  auto data = fine::Atom("data");
}

struct ExMyError {
  int64_t data;

  static constexpr auto module = &atoms::ElixirMyLibMyError;

  static constexpr auto fields() {
    return std::make_tuple(
        std::make_tuple(&ExMyError::data, &atoms::data));
  }

  static constexpr auto is_exception = true;
};
```

Then, we can raise it anywhere in a NIF:

```c++
fine::raise(env, ExMyError{42})
// ** (MyLib.MyError) got error with data 42
```

## Atoms

It is preferable to define atoms as static variables, this way the
corresponding terms are created once, at NIF load time.

```c++
namespace atoms {
  auto hello_world = fine::Atom("hello_world");
}
```

## Result types

When it comes to NIFs, errors often indicate unexpected failures and
raising an exception makes sense, however you may also want to handle
certain errors gracefully by returning `:ok`/`:error` tuples, similarly
to usual Elixir functions. Fine provides `Ok<Args...>` and `Error<Args...>`
types for this purpose.

```c++
fine::Ok<> example() {
  return fine::Ok();
}
// :ok

fine::Ok<int64_t> example() {
  return fine::Ok(1);
}
// {:ok, 1}

fine::Error<> example() {
  return fine::Error();
}
// :error

fine::Error<std::string> example() {
  return fine::Error("something went wrong");
}
// {:error, "something went wrong"}
```

You can use `std::variant` to express a union of possible result types
a NIF may return:

```c++
std::variant<fine::Ok<int64_t, int64_t>, fine::Error<std::string>> divmod(ErlNifEnv *env, int64_t a, int64_t b) {
  if (b == 0) {
    return fine::Error("division by zero");
  }

  return fine::Ok(a / b, a % b);
}
```

Note that if you use a particular union frequently, it may be convenient
to define a type alias with `using`/`typedef` to keep signatures brief.

## Synchronization

Erlang is a multi-process environment where each process is guaranteed to be
isolated from other processes.  When dealing with NIFs, the same C++ function
can be called from multiple Erlang processes simultaneously, leading to race
conditions. While C++ provides synchronization mechanisms, these are unknown to
Erlang and cannot take advantage of tools like *lock checker* or *lcnt*.

Fine provides analogues to `std::mutex` and `std::shared_mutex`, respectively
called `fine::Mutex` and `fine::SharedMutex`. Those are compatible with the
standard mutex wrappers, such as `std::unique_lock` and `std::shared_lock`.
For example:

```c++
#include <fine/sync.hpp>

fine::Mutex mutex;

{
  auto lock = std::unique_lock(mutex);
  ...
}

fine::SharedMutex mutex;

{
  auto lock = std::shared_lock(mutex);
  ...
}
```

While `fine::Mutex` and `fine::SharedMutex` can be created using their default
constructors, users might want to explore their constructors accepting debug
information:
```c++
fine::Mutex mutex("app_name", "type_name");
fine::Mutex mutex("app_name", "type_name", "instance_name");
fine::SharedMutex rwlock("app_name", "type_name");
fine::SharedMutex rwlock("app_name", "type_name", "instance_name");
```

Conventionnally, `"app_name"` is a string representation of the application
associated with the loaded NIFs, `"type_name"` is the type wrapped by the
synchronization primitive, and `"instance_name"` identifies and instance of the
type indivually.  The `"instance_name"` is normally omitted if
the synchronization primitive is global.

Say we were making a wrapper for *libmy_lib* in a app named *my_lib*, we
would create a read/write lock for an object of type *my_object* like so:
```c++
struct my_object;
const char* my_object__name(struct my_object*);

fine::SharedMutex my_object_rwlock("my_lib", "my_object", my_object__name(my_object));
```
## Allocators

For compatibility with the STL, fine supports stateless allocators when
decoding values, while also supporting stateful allocators when encoding
values. The following shows how a custom `MyAllocator` allocator and
`my_memory_resource` memory resource can be used in conjunction with fine:

```c++
template<typename T>
struct MyAllocator { ... };

std::pmr::memory_resource* my_memory_resource = ...;

std::vector<std::pmr::string, MyAllocator<std::pmr::string>> repeat_string(
    ErlNifEnv *,
    std::basic_string<char, std::char_traits<char>, MyAllocator<char>>
        string,
    std::uint64_t repeat) {
  std::vector<std::pmr::string, MyAllocator<std::pmr::string>> strings;

  for (std::uint64_t i = 0; i != repeat; ++i) {
    strings.emplace_back(std::pmr::string(string, my_memory_resource));
  }

  return strings;
}
FINE_NIF(repeat_string, 0);
```

Attempting to decode STL containers making use of `std::pmr::polymorphic_allocator`
will result in the `std::pmr::get_default_resource()` memory resource being
used.

<!-- Docs -->

## Prior work

Some of the ideas have been previously explored by Serge Aleynikov (@saleyn)
and Daniel Goertzen (@goertzenator) ([source](https://github.com/saleyn/nifpp)).

## License

```text
Copyright (c) 2025 Dashbit

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
