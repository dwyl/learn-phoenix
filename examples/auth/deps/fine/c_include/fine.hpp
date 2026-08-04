#ifndef FINE_HPP
#define FINE_HPP
#pragma once

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <type_traits>
#include <variant>
#include <vector>

#include <erl_nif.h>

#if defined(_MSVC_LANG)
#define CPP_VERSION _MSVC_LANG
#else
#define CPP_VERSION __cplusplus
#endif

#if CPP_VERSION < 201703L
#error "elixir-nx/fine only supports C++ 17 and later"
#endif

#if ERL_NIF_MAJOR_VERSION > 2 ||                                               \
    (ERL_NIF_MAJOR_VERSION == 2 && ERL_NIF_MINOR_VERSION >= 17)
#define FINE_ERL_NIF_CHAR_ENCODING ERL_NIF_UTF8
#else
#define FINE_ERL_NIF_CHAR_ENCODING ERL_NIF_LATIN1
#endif

namespace fine {

// Forward declarations

template <typename T> T decode(ErlNifEnv *env, const ERL_NIF_TERM &term);
template <typename T> ERL_NIF_TERM encode(ErlNifEnv *env, const T &value);

template <typename T, typename SFINAE = void> struct Decoder;
template <typename T, typename SFINAE = void> struct Encoder;

namespace __private__ {
std::vector<ErlNifFunc> &get_erl_nif_funcs();
int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info);
} // namespace __private__

// Definitions

namespace __private__ {
inline ERL_NIF_TERM make_atom(ErlNifEnv *env, const char *msg) {
  ERL_NIF_TERM atom;
  if (enif_make_existing_atom(env, msg, &atom, FINE_ERL_NIF_CHAR_ENCODING)) {
    return atom;
  } else {
    return enif_make_atom(env, msg);
  }
}
} // namespace __private__

// A representation of an atom term.
class Atom {
public:
  Atom(std::string name) : name(std::move(name)), term(std::nullopt) {
    if (!Atom::initialized) {
      Atom::atoms.push_back(this);
    }
  }

public:
  const std::string &to_string() const & noexcept { return this->name; }

  std::string to_string() && noexcept { return this->name; }

  bool operator==(const Atom &other) const { return this->name == other.name; }

  bool operator==(const char *other) const { return this->name == other; }

  bool operator<(const Atom &other) const { return this->name < other.name; }

private:
  static void init_atoms(ErlNifEnv *env) {
    for (auto atom : Atom::atoms) {
      atom->term = fine::__private__::make_atom(env, atom->name.c_str());
    }

    Atom::atoms.clear();
    Atom::initialized = true;
  }

  friend struct Encoder<Atom>;
  friend struct Decoder<Atom>;
  friend struct ::std::hash<Atom>;

  friend int __private__::load(ErlNifEnv *env, void **priv_data,
                               ERL_NIF_TERM load_info);

  // We accumulate all globally defined atom objects and create the
  // terms upfront as part of init (called from the NIF load callback).
  inline static std::vector<Atom *> atoms = {};
  inline static bool initialized = false;

  std::string name;
  std::optional<ERL_NIF_UINT> term;
};

namespace __private__::atoms {
inline auto ok = Atom("ok");
inline auto error = Atom("error");
inline auto nil = Atom("nil");
inline auto true_ = Atom("true");
inline auto false_ = Atom("false");
inline auto __struct__ = Atom("__struct__");
inline auto __exception__ = Atom("__exception__");
inline auto message = Atom("message");
inline auto ElixirArgumentError = Atom("Elixir.ArgumentError");
inline auto ElixirRuntimeError = Atom("Elixir.RuntimeError");
} // namespace __private__::atoms

// Represents any term.
//
// This type should be used instead of ERL_NIF_TERM in the NIF signature
// and encode/decode APIs.
class Term {
  // ERL_NIF_TERM is typedef-ed as an integer type. At the moment of
  // writing it is unsigned long int. This means that we cannot define
  // separate Decoder<ERL_NIF_TERM> and Decoder<unsigned long int>,
  // (which could potentially match uint64_t). The same applies to
  // Encoder. For this reason we need a wrapper object for terms, so
  // they can be unambiguously distinguished. We define implicit
  // bidirectional conversion between Term and ERL_NIF_TERM, so that
  // Term is effectively just a typing tag for decoder and encoder
  // (and the nif signature).

public:
  Term() {}

  Term(const ERL_NIF_TERM &term) : term(term) {}

  operator ERL_NIF_TERM() const { return this->term; }

private:
  ERL_NIF_TERM term;
};

inline static bool operator==(const fine::Term &lhs,
                              const fine::Term &rhs) noexcept {
  return enif_compare(lhs, rhs) == 0;
}

inline static bool operator!=(const fine::Term &lhs,
                              const fine::Term &rhs) noexcept {
  return enif_compare(lhs, rhs) != 0;
}

inline static bool operator<(const fine::Term &lhs,
                             const fine::Term &rhs) noexcept {
  return enif_compare(lhs, rhs) < 0;
}

inline static bool operator<=(const fine::Term &lhs,
                              const fine::Term &rhs) noexcept {
  return enif_compare(lhs, rhs) <= 0;
}

inline static bool operator>(const fine::Term &lhs,
                             const fine::Term &rhs) noexcept {
  return enif_compare(lhs, rhs) > 0;
}

inline static bool operator>=(const fine::Term &lhs,
                              const fine::Term &rhs) noexcept {
  return enif_compare(lhs, rhs) >= 0;
}

// Represents a `:ok` tagged tuple, useful as a NIF result.
template <typename... Args> class Ok {
public:
  using Items = std::tuple<Args...>;

  explicit Ok(Args... items) : m_items{std::move(items)...} {}

  template <typename... UArgs>
  Ok(const Ok<UArgs...> &other) : m_items(other.items()) {}

  template <typename... UArgs>
  Ok(Ok<UArgs...> &&other) : m_items(std::move(other).items()) {}

  const Items &items() const & noexcept { return m_items; }

  Items &items() & noexcept { return m_items; }

  Items &&items() && noexcept { return std::move(m_items); }

private:
  Items m_items;
};

// Represents a `:error` tagged tuple, useful as a NIF result.
template <typename... Args> class Error {
public:
  using Items = std::tuple<Args...>;

  explicit Error(Args... items) : m_items{std::move(items)...} {}

  template <typename... UArgs>
  Error(const Error<UArgs...> &other) : m_items(other.items()) {}

  template <typename... UArgs>
  Error(Error<UArgs...> &&other) : m_items(std::move(other).items()) {}

  const Items &items() const & noexcept { return m_items; }

  Items &items() & noexcept { return m_items; }

  Items &&items() && noexcept { return std::move(m_items); }

private:
  Items m_items;
};

namespace __private__ {
template <typename T> struct ResourceWrapper {
  T resource;
  bool initialized;

  static void dtor(ErlNifEnv *env, void *ptr) {
    auto resource_wrapper = reinterpret_cast<ResourceWrapper<T> *>(ptr);

    if (resource_wrapper->initialized) {
      if constexpr (has_destructor<T>::value) {
        resource_wrapper->resource.destructor(env);
      }
      resource_wrapper->resource.~T();
    }
  }

  template <typename U, typename = void>
  struct has_destructor : std::false_type {};

  template <typename U>
  struct has_destructor<
      U,
      typename std::enable_if<std::is_same<
          decltype(std::declval<U>().destructor(std::declval<ErlNifEnv *>())),
          void>::value>::type> : std::true_type {};
};
} // namespace __private__

// A smart pointer that retains ownership of a resource object.
template <typename T> class ResourcePtr {
  // For more context see [1] and [2].
  //
  // [1]: https://stackoverflow.com/a/3279550
  // [2]: https://stackoverflow.com/a/5695855

public:
  // Make default constructor public, so that classes with ResourcePtr
  // field can also have default constructor.
  ResourcePtr() : ptr(nullptr) {}

  ResourcePtr(const ResourcePtr<T> &other) : ptr(other.ptr) {
    if (this->ptr != nullptr) {
      enif_keep_resource(reinterpret_cast<void *>(this->ptr));
    }
  }

  ResourcePtr(ResourcePtr<T> &&other) : ResourcePtr() { swap(other, *this); }

  ~ResourcePtr() {
    if (this->ptr != nullptr) {
      enif_release_resource(reinterpret_cast<void *>(this->ptr));
    }
  }

  ResourcePtr<T> &operator=(ResourcePtr<T> other) {
    swap(*this, other);
    return *this;
  }

  T &operator*() const { return this->ptr->resource; }

  T *operator->() const { return &this->ptr->resource; }

  T *get() const { return &this->ptr->resource; }

  friend void swap(ResourcePtr<T> &left, ResourcePtr<T> &right) {
    using std::swap;
    swap(left.ptr, right.ptr);
  }

private:
  // This constructor assumes the pointer is already accounted for in
  // the resource reference count. Since it is private, we guarantee
  // this in all the callers.
  ResourcePtr(__private__::ResourceWrapper<T> *ptr) : ptr(ptr) {}

  // Friend functions that use the resource_type static member or the
  // private constructor.

  template <typename U, typename... Args>
  friend ResourcePtr<U> make_resource(Args &&...args);

  friend class Registration;

  friend struct Decoder<ResourcePtr<T>>;

  inline static ErlNifResourceType *resource_type = nullptr;

  __private__::ResourceWrapper<T> *ptr;
};

// Allocates a new resource object, invoking its constructor with the
// given arguments.
template <typename T, typename... Args>
ResourcePtr<T> make_resource(Args &&...args) {
  auto type = ResourcePtr<T>::resource_type;

  if (type == nullptr) {
    throw std::runtime_error(
        "calling make_resource with unexpected type. Make sure"
        " to register your resource type with the FINE_RESOURCE macro");
  }

  void *allocation_ptr =
      enif_alloc_resource(type, sizeof(__private__::ResourceWrapper<T>));

  auto resource_wrapper =
      reinterpret_cast<__private__::ResourceWrapper<T> *>(allocation_ptr);

  // We create ResourcePtr right away, to make sure the resource is
  // properly released in case the constructor below throws
  auto resource = ResourcePtr<T>(resource_wrapper);

  // We use a wrapper struct with an extra field to track if the
  // resource has actually been initialized. This way if the constructor
  // below throws, we can skip the destructor calls in the Erlang dtor
  resource_wrapper->initialized = false;

  // Invoke the constructor with prefect forwarding to initialize the
  // object at the VM-allocated memory
  new (&resource_wrapper->resource) T(std::forward<Args>(args)...);

  resource_wrapper->initialized = true;

  return resource;
}

// Creates a binary term pointing to the given buffer.
//
// The buffer is managed by the resource object and should be deallocated
// once the resource is destroyed.
template <typename T>
Term make_resource_binary(ErlNifEnv *env, ResourcePtr<T> resource,
                          const char *data, size_t size) {
  return enif_make_resource_binary(
      env, reinterpret_cast<void *>(resource.get()), data, size);
}

// Creates a binary term copying data from the given buffer.
//
// This is useful when returning large binary from a NIF and the source
// buffer does not outlive the return.
inline Term make_new_binary(ErlNifEnv *env, const char *data, size_t size) {
  ERL_NIF_TERM term;
  auto term_data = enif_make_new_binary(env, size, &term);
  if (term_data == nullptr) {
    throw std::runtime_error(
        "make_new_binary failed, failed to allocate new binary");
  }
  memcpy(term_data, data, size);
  return term;
}

// Decodes the given Erlang term as a value of the specified type.
//
// The given type must have a specialized Decoder<T> implementation.
template <typename T> T decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
  return Decoder<T>::decode(env, term);
}

// Encodes the given value as a Erlang term.
//
// The value type must have a specialized Encoder<T> implementation.
template <typename T> ERL_NIF_TERM encode(ErlNifEnv *env, const T &value) {
  return Encoder<T>::encode(env, value);
}

// We want decode to return the value, and since the argument types
// are always the same, we need template specialization, so that the
// caller can explicitly specify the desired type. However, in order
// to implement decode for a type such as std::vector<T> we need
// partial specialization, and that is not supported for functions.
// To solve this, we specialize a struct instead and have the decode
// logic in a static member function.
//
// In case of encode, the argument type differs, so we could use
// function overloading. That said, we pick struct specialization as
// well for consistency with decode. This approach also prevents from
// implicit argument conversion, which is arguably good in this case,
// as it makes the encoding explicit.

template <typename T, typename> struct Decoder {};

template <typename T, typename> struct Encoder {};

template <> struct Decoder<Term> {
  static Term decode(ErlNifEnv *, const ERL_NIF_TERM &term) {
    return Term(term);
  }
};

template <> struct Decoder<int64_t> {
  static int64_t decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
    int64_t integer;
    if (!enif_get_int64(env, term,
                        reinterpret_cast<ErlNifSInt64 *>(&integer))) {
      throw std::invalid_argument("decode failed, expected an integer");
    }
    return integer;
  }
};

template <> struct Decoder<uint64_t> {
  static uint64_t decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
    uint64_t integer;
    if (!enif_get_uint64(env, term,
                         reinterpret_cast<ErlNifUInt64 *>(&integer))) {
      throw std::invalid_argument(
          "decode failed, expected an unsigned integer");
    }
    return integer;
  }
};

template <> struct Decoder<double> {
  static double decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
    double number;
    if (!enif_get_double(env, term, &number)) {
      throw std::invalid_argument("decode failed, expected a float");
    }
    return number;
  }
};

template <> struct Decoder<bool> {
  static bool decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
    char atom_string[6];
    auto length = enif_get_atom(env, term, atom_string, 6, ERL_NIF_LATIN1);

    if (length == 5 && strcmp(atom_string, "true") == 0) {
      return true;
    }

    if (length == 6 && strcmp(atom_string, "false") == 0) {
      return false;
    }

    throw std::invalid_argument("decode failed, expected a boolean");
  }
};

template <> struct Decoder<ErlNifPid> {
  static ErlNifPid decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
    ErlNifPid pid;
    if (!enif_is_pid(env, term)) {
      throw std::invalid_argument("decode failed, expected a local pid");
    }
    if (!enif_get_local_pid(env, term, &pid)) {
      // If the term is a PID and it is not local, it means it's a remote PID.
      throw std::invalid_argument(
          "decode failed, expected a local pid, but got a remote one. NIFs can "
          "only send messages to local PIDs and remote PIDs cannot be decoded");
    }
    return pid;
  }
};

template <> struct Decoder<ErlNifBinary> {
  static ErlNifBinary decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
    ErlNifBinary binary;
    if (!enif_inspect_binary(env, term, &binary)) {
      throw std::invalid_argument("decode failed, expected a binary");
    }
    return binary;
  }
};

template <> struct Decoder<std::string_view> {
  static std::string_view decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
    auto binary = fine::decode<ErlNifBinary>(env, term);
    return std::string_view(reinterpret_cast<const char *>(binary.data),
                            binary.size);
  }
};

template <typename Alloc>
struct Decoder<std::basic_string<char, std::char_traits<char>, Alloc>> {
  using string = std::basic_string<char, std::char_traits<char>, Alloc>;

  static string decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
    return string(fine::decode<std::string_view>(env, term));
  }
};

template <> struct Decoder<Atom> {
  static Atom decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
    unsigned int length;
    if (!enif_get_atom_length(env, term, &length, FINE_ERL_NIF_CHAR_ENCODING)) {
      throw std::invalid_argument("decode failed, expected an atom");
    }

    auto buffer = std::make_unique<char[]>(length + 1);

    // Note that enif_get_atom writes the NULL byte at the end
    if (!enif_get_atom(env, term, buffer.get(), length + 1,
                       FINE_ERL_NIF_CHAR_ENCODING)) {
      throw std::invalid_argument("decode failed, expected an atom");
    }

    return Atom(std::string(buffer.get(), length));
  }
};

template <typename T> struct Decoder<std::optional<T>> {
  static std::optional<T> decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
    char atom_string[4];
    if (enif_get_atom(env, term, atom_string, 4, ERL_NIF_LATIN1) == 4) {
      if (strcmp(atom_string, "nil") == 0) {
        return std::nullopt;
      }
    }

    return fine::decode<T>(env, term);
  }
};

template <typename... Args> struct Decoder<std::variant<Args...>> {
  static std::variant<Args...> decode(ErlNifEnv *env,
                                      const ERL_NIF_TERM &term) {
    return do_decode<Args...>(env, term);
  }

private:
  template <typename T, typename... Rest>
  static std::variant<Args...> do_decode(ErlNifEnv *env,
                                         const ERL_NIF_TERM &term) {
    try {
      return fine::decode<T>(env, term);
    } catch (const std::invalid_argument &) {
      if constexpr (sizeof...(Rest) > 0) {
        return do_decode<Rest...>(env, term);
      } else {
        throw std::invalid_argument(
            "decode failed, none of the variant types could be decoded");
      }
    }
  }
};

template <typename... Args> struct Decoder<std::tuple<Args...>> {
  static std::tuple<Args...> decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
    constexpr auto expected_size = sizeof...(Args);

    int size;
    const ERL_NIF_TERM *terms;
    if (!enif_get_tuple(env, term, &size, &terms)) {
      throw std::invalid_argument("decode failed, expected a tuple");
    }

    if (size != expected_size) {
      throw std::invalid_argument("decode failed, expected tuple to have " +
                                  std::to_string(expected_size) +
                                  " elements, but had " + std::to_string(size));
    }

    return do_decode(env, terms, std::make_index_sequence<sizeof...(Args)>());
  }

private:
  template <std::size_t... Indices>
  static std::tuple<Args...> do_decode(ErlNifEnv *env,
                                       const ERL_NIF_TERM *terms,
                                       std::index_sequence<Indices...>) {
    return std::make_tuple(fine::decode<Args>(env, terms[Indices])...);
  }
};

template <typename T, typename Alloc> struct Decoder<std::vector<T, Alloc>> {
  static std::vector<T, Alloc> decode(ErlNifEnv *env,
                                      const ERL_NIF_TERM &term) {
    unsigned int length;

    if (!enif_get_list_length(env, term, &length)) {
      throw std::invalid_argument("decode failed, expected a list");
    }

    std::vector<T, Alloc> vector;
    vector.reserve(length);

    auto list = term;

    ERL_NIF_TERM head, tail;
    while (enif_get_list_cell(env, list, &head, &tail)) {
      auto elem = fine::decode<T>(env, head);
      vector.emplace_back(std::move(elem));
      list = tail;
    }

    return vector;
  }
};

template <typename K, typename V, typename Compare, typename Alloc>
struct Decoder<std::map<K, V, Compare, Alloc>> {
  static std::map<K, V, Compare, Alloc> decode(ErlNifEnv *env,
                                               const ERL_NIF_TERM &term) {
    std::map<K, V, Compare, Alloc> map;

    ERL_NIF_TERM key_term, value_term;
    ErlNifMapIterator iter;
    if (!enif_map_iterator_create(env, term, &iter,
                                  ERL_NIF_MAP_ITERATOR_FIRST)) {
      throw std::invalid_argument("decode failed, expected a map");
    }

    // Define RAII cleanup for the iterator
    auto cleanup = IterCleanup{env, iter};

    while (enif_map_iterator_get_pair(env, &iter, &key_term, &value_term)) {
      auto key = fine::decode<K>(env, key_term);
      auto value = fine::decode<V>(env, value_term);

      map.insert_or_assign(std::move(key), std::move(value));

      enif_map_iterator_next(env, &iter);
    }

    return map;
  }

private:
  struct IterCleanup {
    ErlNifEnv *env;
    ErlNifMapIterator iter;

    ~IterCleanup() { enif_map_iterator_destroy(env, &iter); }
  };
};

template <typename T> struct Decoder<ResourcePtr<T>> {
  static ResourcePtr<T> decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
    void *ptr;
    auto type = ResourcePtr<T>::resource_type;

    if (!enif_get_resource(env, term, type, &ptr)) {
      throw std::invalid_argument(
          "decode failed, expected a resource reference");
    }

    enif_keep_resource(ptr);

    return ResourcePtr<T>(
        reinterpret_cast<__private__::ResourceWrapper<T> *>(ptr));
  }
};

template <typename T>
struct Decoder<T, std::void_t<decltype(T::module), decltype(T::fields)>> {
  static T decode(ErlNifEnv *env, const ERL_NIF_TERM &term) {
    ERL_NIF_TERM struct_value;
    if (!enif_get_map_value(env, term,
                            encode(env, __private__::atoms::__struct__),
                            &struct_value)) {
      throw std::invalid_argument("decode failed, expected a struct");
    }

    // Make sure __struct__ matches
    const auto &struct_atom = *T::module;
    if (enif_compare(struct_value, encode(env, struct_atom)) != 0) {
      throw std::invalid_argument("decode failed, expected a " +
                                  struct_atom.to_string() + " struct");
    }

    T ex_struct;

    constexpr auto fields = T::fields();

    std::apply(
        [&](auto... field) {
          (set_field(env, term, ex_struct, std::get<0>(field),
                     std::get<1>(field)),
           ...);
        },
        fields);

    return ex_struct;
  }

private:
  template <typename U>
  static void set_field(ErlNifEnv *env, ERL_NIF_TERM term, T &ex_struct,
                        U T::*field_ptr, const Atom *atom) {
    ERL_NIF_TERM value;
    if (!enif_get_map_value(env, term, encode(env, *atom), &value)) {
      throw std::invalid_argument(
          "decode failed, expected the struct to have " + atom->to_string() +
          " field");
    }

    ex_struct.*(field_ptr) = fine::decode<U>(env, value);
  }
};

template <> struct Encoder<Term> {
  static ERL_NIF_TERM encode(ErlNifEnv *, const Term &term) { return term; }
};

template <> struct Encoder<int64_t> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const int64_t &integer) {
    return enif_make_int64(env, integer);
  }
};

template <> struct Encoder<uint64_t> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const uint64_t &integer) {
    return enif_make_uint64(env, integer);
  }
};

template <> struct Encoder<double> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const double &number) {
    return enif_make_double(env, number);
  }
};

template <> struct Encoder<bool> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const bool &boolean) {
    return fine::encode(env, boolean ? __private__::atoms::true_
                                     : __private__::atoms::false_);
  }
};

// enif_make_pid is a macro that does a cast (const ERL_NIF_TERM)
// and GCC complains that the cast is ignored, so we ignore this
// specific warning explicitly here.
#ifdef __GNUC__
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wignored-qualifiers"
#endif

template <> struct Encoder<ErlNifPid> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const ErlNifPid &pid) {
    return enif_make_pid(env, &pid);
  }
};

#ifdef __GNUC__
#pragma GCC diagnostic pop
#endif

template <> struct Encoder<ErlNifBinary> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const ErlNifBinary &binary) {
    return enif_make_binary(env, const_cast<ErlNifBinary *>(&binary));
  }
};

template <> struct Encoder<std::string_view> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const std::string_view &string) {
    ERL_NIF_TERM term;
    auto data = enif_make_new_binary(env, string.length(), &term);
    if (data == nullptr) {
      throw std::runtime_error("encode failed, failed to allocate new binary");
    }
    memcpy(data, string.data(), string.length());
    return term;
  }
};

template <typename Alloc>
struct Encoder<std::basic_string<char, std::char_traits<char>, Alloc>> {
  static ERL_NIF_TERM
  encode(ErlNifEnv *env,
         const std::basic_string<char, std::char_traits<char>, Alloc> &string) {
    return fine::encode<std::string_view>(env, string);
  }
};

template <> struct Encoder<Atom> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const Atom &atom) {
    if (atom.term) {
      return atom.term.value();
    } else {
      return fine::__private__::make_atom(env, atom.name.c_str());
    }
  }
};

template <> struct Encoder<std::nullopt_t> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const std::nullopt_t &) {
    return fine::encode(env, __private__::atoms::nil);
  }
};

template <typename T> struct Encoder<std::optional<T>> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const std::optional<T> &optional) {
    if (optional) {
      return fine::encode(env, optional.value());
    } else {
      return fine::encode(env, __private__::atoms::nil);
    }
  }
};

template <typename... Args> struct Encoder<std::variant<Args...>> {
  static ERL_NIF_TERM encode(ErlNifEnv *env,
                             const std::variant<Args...> &variant) {
    return do_encode<Args...>(env, variant);
  }

private:
  template <typename T, typename... Rest>
  static ERL_NIF_TERM do_encode(ErlNifEnv *env,
                                const std::variant<Args...> &variant) {
    if (auto value = std::get_if<T>(&variant)) {
      return fine::encode(env, *value);
    }

    if constexpr (sizeof...(Rest) > 0) {
      return do_encode<Rest...>(env, variant);
    } else {
      throw std::runtime_error("unreachable");
    }
  }
};

template <typename... Args> struct Encoder<std::tuple<Args...>> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const std::tuple<Args...> &tuple) {
    return do_encode(env, tuple, std::make_index_sequence<sizeof...(Args)>());
  }

private:
  template <std::size_t... Indices>
  static ERL_NIF_TERM do_encode(ErlNifEnv *env,
                                const std::tuple<Args...> &tuple,
                                std::index_sequence<Indices...>) {
    constexpr auto size = sizeof...(Args);
    return enif_make_tuple(env, size,
                           fine::encode(env, std::get<Indices>(tuple))...);
  }
};

template <typename T, typename Alloc> struct Encoder<std::vector<T, Alloc>> {
  static ERL_NIF_TERM encode(ErlNifEnv *env,
                             const std::vector<T, Alloc> &vector) {
    auto terms = std::vector<ERL_NIF_TERM>();
    terms.reserve(vector.size());

    for (const auto &item : vector) {
      terms.push_back(fine::encode(env, item));
    }

    return enif_make_list_from_array(env, terms.data(),
                                     static_cast<unsigned int>(terms.size()));
  }
};

template <typename K, typename V, typename Compare, typename Alloc>
struct Encoder<std::map<K, V, Compare, Alloc>> {
  static ERL_NIF_TERM encode(ErlNifEnv *env,
                             const std::map<K, V, Compare, Alloc> &map) {
    auto keys = std::vector<ERL_NIF_TERM>();
    auto values = std::vector<ERL_NIF_TERM>();

    for (const auto &[key, value] : map) {
      keys.push_back(fine::encode(env, key));
      values.push_back(fine::encode(env, value));
    }

    ERL_NIF_TERM map_term;
    if (!enif_make_map_from_arrays(env, keys.data(), values.data(), keys.size(),
                                   &map_term)) {
      throw std::runtime_error("encode failed, failed to make a map");
    }

    return map_term;
  }
};

template <typename T> struct Encoder<ResourcePtr<T>> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const ResourcePtr<T> &resource) {
    return enif_make_resource(env, reinterpret_cast<void *>(resource.get()));
  }
};

template <typename T>
struct Encoder<T, std::void_t<decltype(T::module), decltype(T::fields)>> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const T &ex_struct) {
    const auto &struct_atom = *T::module;
    constexpr auto fields = T::fields();
    constexpr auto is_exception = get_is_exception();

    constexpr auto num_fields = std::tuple_size<decltype(fields)>::value;
    constexpr auto num_extra_fields = is_exception ? 2 : 1;

    ERL_NIF_TERM keys[num_extra_fields + num_fields];
    ERL_NIF_TERM values[num_extra_fields + num_fields];

    keys[0] = fine::encode(env, __private__::atoms::__struct__);
    values[0] = fine::encode(env, struct_atom);

    if constexpr (is_exception) {
      keys[1] = fine::encode(env, __private__::atoms::__exception__);
      values[1] = fine::encode(env, __private__::atoms::true_);
    }

    put_key_values(env, ex_struct, keys + num_extra_fields,
                   values + num_extra_fields,
                   std::make_index_sequence<num_fields>());

    ERL_NIF_TERM map;
    if (!enif_make_map_from_arrays(env, keys, values,
                                   num_extra_fields + num_fields, &map)) {
      throw std::runtime_error("encode failed, failed to make a map");
    }

    return map;
  }

private:
  template <std::size_t... Indices>
  static void put_key_values(ErlNifEnv *env, const T &ex_struct,
                             ERL_NIF_TERM keys[], ERL_NIF_TERM values[],
                             std::index_sequence<Indices...>) {
    constexpr auto fields = T::fields();

    std::apply(
        [&](auto... field) {
          ((keys[Indices] = fine::encode(env, *std::get<1>(field)),
            values[Indices] =
                fine::encode(env, ex_struct.*(std::get<0>(field)))),
           ...);
        },
        fields);
  }

  static constexpr bool get_is_exception() {
    if constexpr (has_is_exception<T>::value) {
      return T::is_exception;
    } else {
      return false;
    }
  }

  template <typename U, typename = void>
  struct has_is_exception : std::false_type {};

  template <typename U>
  struct has_is_exception<U, std::void_t<decltype(U::is_exception)>>
      : std::true_type {};
};

template <typename... Args> struct Encoder<Ok<Args...>> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const Ok<Args...> &ok) {
    auto tag = __private__::atoms::ok;

    if constexpr (sizeof...(Args) > 0) {
      return fine::encode(env, std::tuple_cat(std::tuple(tag), ok.items()));
    } else {
      return fine::encode(env, tag);
    }
  }
};

template <typename... Args> struct Encoder<Error<Args...>> {
  static ERL_NIF_TERM encode(ErlNifEnv *env, const Error<Args...> &error) {
    auto tag = __private__::atoms::error;

    if constexpr (sizeof...(Args) > 0) {
      return fine::encode(env, std::tuple_cat(std::tuple(tag), error.items()));
    } else {
      return fine::encode(env, tag);
    }
  }
};

namespace __private__ {
class ExceptionError : public std::exception {
public:
  ERL_NIF_TERM reason;

  ExceptionError(ERL_NIF_TERM reason) : reason(reason) {}
  const char *what() const noexcept { return "erlang exception raised"; }
};
} // namespace __private__

// Raises an Elixir exception with the given value as reason.
template <typename T> void raise(ErlNifEnv *env, const T &value) {
  auto term = encode(env, value);
  throw __private__::ExceptionError(term);
}

// Mechanism for accumulating information via static object definitions.
class Registration {
public:
  template <typename T>
  static Registration register_resource(const char *name) {
    Registration::resources.push_back({&fine::ResourcePtr<T>::resource_type,
                                       name,
                                       __private__::ResourceWrapper<T>::dtor});
    return {};
  }

  static Registration register_nif(ErlNifFunc erl_nif_func) {
    Registration::erl_nif_funcs.push_back(erl_nif_func);
    return {};
  }

private:
  static bool init_resources(ErlNifEnv *env) {
    for (const auto &[resource_type_ptr, name, dtor] :
         Registration::resources) {
      auto flags = ERL_NIF_RT_CREATE;
      auto type = enif_open_resource_type(env, NULL, name, dtor, flags, NULL);

      if (type) {
        *resource_type_ptr = type;
      } else {
        return false;
      }
    }

    Registration::resources.clear();

    return true;
  }

  friend std::vector<ErlNifFunc> &__private__::get_erl_nif_funcs();

  friend int __private__::load(ErlNifEnv *env, void **priv_data,
                               ERL_NIF_TERM load_info);

  inline static std::vector<std::tuple<ErlNifResourceType **, const char *,
                                       void (*)(ErlNifEnv *, void *)>>
      resources = {};

  inline static std::vector<ErlNifFunc> erl_nif_funcs = {};
};

// NIF definitions

namespace __private__ {
inline ERL_NIF_TERM raise_error_with_message(ErlNifEnv *env, Atom module,
                                             std::string message) {
  ERL_NIF_TERM keys[3] = {fine::encode(env, __private__::atoms::__struct__),
                          fine::encode(env, __private__::atoms::__exception__),
                          fine::encode(env, __private__::atoms::message)};
  ERL_NIF_TERM values[3] = {
      fine::encode(env, module),
      fine::encode(env, __private__::atoms::true_),
      fine::encode(env, message),
  };

  ERL_NIF_TERM map;
  if (!enif_make_map_from_arrays(env, keys, values, 3, &map)) {
    return enif_raise_exception(env, encode(env, message));
  }

  return enif_raise_exception(env, map);
}

template <typename Return, typename... Args, std::size_t... Indices>
ERL_NIF_TERM nif_impl(ErlNifEnv *env, const ERL_NIF_TERM argv[],
                      Return (*fun)(ErlNifEnv *, Args...),
                      std::index_sequence<Indices...>) {
  try {
    auto result = fun(env, decode<Args>(env, argv[Indices])...);
    return encode(env, result);
  } catch (const ExceptionError &error) {
    return enif_raise_exception(env, error.reason);
  } catch (const std::invalid_argument &error) {
    return raise_error_with_message(
        env, __private__::atoms::ElixirArgumentError, error.what());
  } catch (const std::runtime_error &error) {
    return raise_error_with_message(env, __private__::atoms::ElixirRuntimeError,
                                    error.what());
  } catch (...) {
    return raise_error_with_message(env, __private__::atoms::ElixirRuntimeError,
                                    "unknown exception thrown within NIF");
  }
}
} // namespace __private__

template <typename Return, typename... Args>
ERL_NIF_TERM nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[],
                 Return (*fun)(ErlNifEnv *, Args...)) {
  const auto num_args = sizeof...(Args);

  if (num_args != argc) {
    return enif_raise_exception(
        env, encode(env, std::string("wrong number of arguments")));
  }

  return __private__::nif_impl(env, argv, fun,
                               std::make_index_sequence<sizeof...(Args)>());
}

template <typename Ret, typename... Args>
constexpr unsigned int nif_arity(Ret (*)(Args...)) {
  return sizeof...(Args) - 1;
}

namespace __private__ {
inline std::vector<ErlNifFunc> &get_erl_nif_funcs() {
  return Registration::erl_nif_funcs;
}

inline int load(ErlNifEnv *env, void **, ERL_NIF_TERM) {
  Atom::init_atoms(env);

  if (!Registration::init_resources(env)) {
    return -1;
  }

  return 0;
}
} // namespace __private__

// Macros

#define FINE_NIF(name, flags)                                                  \
  static ERL_NIF_TERM name##_nif(ErlNifEnv *env, int argc,                     \
                                 const ERL_NIF_TERM argv[]) {                  \
    return fine::nif(env, argc, argv, name);                                   \
  }                                                                            \
  auto __nif_registration_##name = fine::Registration::register_nif(           \
      {#name, fine::nif_arity(name), name##_nif, flags});                      \
  static_assert(true, "require a semicolon after the macro")

// Note that we use static, in case FINE_REASOURCE is used in another
// translation unit on the same line.

#define FINE_RESOURCE(class_name)                                              \
  static auto __FINE_CONCAT__(__resource_registration_, __LINE__) =            \
      fine::Registration::register_resource<class_name>(#class_name);          \
  static_assert(true, "require a semicolon after the macro")

// An extra level of indirection is necessary to make sure __LINE__
// is expanded before concatenation.
#define __FINE_CONCAT__(a, b) __FINE_CONCAT_IMPL__(a, b)
#define __FINE_CONCAT_IMPL__(a, b) a##b

// This is a modified version of ERL_NIF_INIT that points to the
// registered NIF functions and also sets the load callback.

#define FINE_INIT(name)                                                        \
  ERL_NIF_INIT_PROLOGUE                                                        \
  ERL_NIF_INIT_GLOB                                                            \
  ERL_NIF_INIT_DECL(NAME);                                                     \
  ERL_NIF_INIT_DECL(NAME) {                                                    \
    auto &nif_funcs = fine::__private__::get_erl_nif_funcs();                  \
    auto num_funcs = static_cast<int>(nif_funcs.size());                       \
    auto funcs = nif_funcs.data();                                             \
    auto load = fine::__private__::load;                                       \
    static ErlNifEntry entry = {ERL_NIF_MAJOR_VERSION,                         \
                                ERL_NIF_MINOR_VERSION,                         \
                                name,                                          \
                                num_funcs,                                     \
                                funcs,                                         \
                                load,                                          \
                                NULL,                                          \
                                NULL,                                          \
                                NULL,                                          \
                                ERL_NIF_VM_VARIANT,                            \
                                1,                                             \
                                sizeof(ErlNifResourceTypeInit),                \
                                ERL_NIF_MIN_ERTS_VERSION};                     \
    ERL_NIF_INIT_BODY;                                                         \
    return &entry;                                                             \
  }                                                                            \
  ERL_NIF_INIT_EPILOGUE                                                        \
  static_assert(true, "require a semicolon after the macro")

} // namespace fine

namespace std {
template <> struct hash<::fine::Term> {
  size_t operator()(const ::fine::Term &term) noexcept {
    return enif_hash(ERL_NIF_INTERNAL_HASH, term, 0);
  }
};

template <> struct hash<::fine::Atom> {
  size_t operator()(const ::fine::Atom &atom) noexcept {
    return std::hash<std::string_view>{}(atom.to_string());
  }
};
} // namespace std

#endif
