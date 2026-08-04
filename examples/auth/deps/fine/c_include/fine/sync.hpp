#ifndef FINE_SYNC_HPP
#define FINE_SYNC_HPP
#pragma once

#include <cstddef>
#include <memory>
#include <mutex> // IWYU pragma: keep
#include <optional>
#include <shared_mutex> // IWYU pragma: keep
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>

#include <erl_nif.h>

namespace fine {
// Creates a mutually exclusive lock backed by Erlang.
//
// This mutex type implements the Lockable requirement, ensuring it can be used
// with `std::unique_lock` and family.
class Mutex final {
public:
  // Creates an unnamed Mutex.
  Mutex() : m_handle(enif_mutex_create(nullptr)) {
    if (!m_handle) {
      throw std::runtime_error("failed to create mutex");
    }
  }

  // Creates a Mutex from a ErlNifMutex handle.
  explicit Mutex(ErlNifMutex *handle) noexcept : m_handle(handle) {}

  // Creates a Mutex with the given debug information.
  Mutex(std::string_view app, std::string_view type,
        std::optional<std::string_view> instance = std::nullopt) {
    std::stringstream stream;
    stream << app << "." << type;

    if (instance) {
      stream << "[" << *instance << "]";
    }

    std::string str = std::move(stream).str();

    // We make use of `const_cast` to create the mutex, but this exceptional
    // situation is acceptable, as `enif_mutex_create` doesn't modify the name:
    //   https://github.com/erlang/otp/blob/a87183f1eb847119b6ecc83054bf13c26b8ccfaa/erts/emulator/beam/erl_drv_thread.c#L166-L169
    auto *handle = enif_mutex_create(const_cast<char *>(str.c_str()));
    if (handle == nullptr) {
      throw std::runtime_error("failed to create mutex");
    }
    m_handle.reset(handle);
  }

  // Converts this Mutex to a ErlNifMutex handle.
  //
  // Ownership still belongs to this instance.
  operator ErlNifMutex *() const & noexcept { return m_handle.get(); }

  // Releases ownership of the ErlNifMutex handle to the caller.
  //
  // This operation is only possible by:
  // ```
  // static_cast<ErlNifMutex*>(std::move(mutex))
  // ```
  explicit operator ErlNifMutex *() && noexcept { return m_handle.release(); }

  // Locks the Mutex. The calling thread is blocked until the Mutex has been
  // locked. A thread that has currently locked the Mutex cannot lock the same
  // Mutex again.
  //
  // This function is thread-safe.
  void lock() noexcept { enif_mutex_lock(m_handle.get()); }

  // Unlocks a Mutex. The Mutex currently must be locked by the calling thread.
  //
  // This function is thread-safe.
  void unlock() noexcept { enif_mutex_unlock(m_handle.get()); }

  // Tries to lock a Mutex. A thread that has currently locked the Mutex cannot
  // try to lock the same Mutex again.
  //
  // This function is thread-safe.
  bool try_lock() noexcept { return enif_mutex_trylock(m_handle.get()) == 0; }

private:
  struct Deleter {
    void operator()(ErlNifMutex *handle) const noexcept {
      enif_mutex_destroy(handle);
    }
  };
  std::unique_ptr<ErlNifMutex, Deleter> m_handle;
};

// Creates a read-write lock backed by Erlang.
//
// This lock type implements the Lockable and SharedLockable requirements,
// ensuring it can be used with `std::unique_lock`, `std::shared_lock`, etc.
class SharedMutex final {
public:
  // Creates an unnamed SharedMutex.
  SharedMutex() : m_handle(enif_rwlock_create(nullptr)) {
    if (!m_handle) {
      throw std::runtime_error("failed to create rwlock");
    }
  }

  // Creates a SharedMutex from a ErlNifRWLock handle.
  explicit SharedMutex(ErlNifRWLock *handle) noexcept : m_handle(handle) {}

  // Creates a SharedMutex with the given name.
  SharedMutex(std::string_view app, std::string_view type,
              std::optional<std::string_view> instance = std::nullopt) {
    std::stringstream stream;
    stream << app << "." << type;

    if (instance) {
      stream << "[" << *instance << "]";
    }

    std::string str = std::move(stream).str();

    // We make use of `const_cast` to create the rwlock, but this exceptional
    // situation is acceptable, as `enif_rwlock_create` doesn't modify the name:
    //   https://github.com/erlang/otp/blob/a87183f1eb847119b6ecc83054bf13c26b8ccfaa/ert/emulator/beam/erl_drv_thread.c#L337-L340
    auto *handle = enif_rwlock_create(const_cast<char *>(str.c_str()));
    if (handle == nullptr) {
      throw std::runtime_error("failed to create rwlock");
    }
    m_handle.reset(handle);
  }

  // Converts this SharedMutex to a ErlNifSharedMutex handle.
  //
  // Ownership still belongs to this instance.
  operator ErlNifRWLock *() const & noexcept { return m_handle.get(); }

  // Releases ownership of the ErlNifRWLock handle to the caller.
  //
  // This operation is only possible by:
  // ```
  // static_cast<ErlNifRWLock*>(std::move(rwlock))
  // ```
  explicit operator ErlNifRWLock *() && noexcept { return m_handle.release(); }

  // Read locks a SharedMutex. The calling thread is blocked until the
  // SharedMutex has been read locked. A thread that currently has read or
  // read/write locked the SharedMutex cannot lock the same SharedMutex again.
  //
  // This function is thread-safe.
  void lock_shared() noexcept { enif_rwlock_rlock(m_handle.get()); }

  // Read unlocks a SharedMutex. The SharedMutex currently must be read locked
  // by the calling thread.
  //
  // This function is thread-safe.
  void unlock_shared() noexcept { enif_rwlock_runlock(m_handle.get()); }

  // Read/write locks a SharedMutex. The calling thread is blocked until the
  // SharedMutex has been read/write locked. A thread that currently has read or
  // read/write locked the SharedMutex cannot lock the same SharedMutex again.
  //
  // This function is thread-safe.
  void lock() noexcept { enif_rwlock_rwlock(m_handle.get()); }

  // Read/write unlocks a SharedMutex. The SharedMutex currently must be
  // read/write locked by the calling thread.
  //
  // This function is thread-safe.
  void unlock() noexcept { enif_rwlock_rwunlock(m_handle.get()); }

  // Tries to read lock a SharedMutex.
  //
  // This function is thread-safe.
  bool try_lock_shared() noexcept {
    return enif_rwlock_tryrlock(m_handle.get()) == 0;
  }

  // Tries to read/write lock a SharedMutex. A thread that currently has read
  // or read/write locked the SharedMutex cannot try to lock the same
  // SharedMutex again.
  //
  // This function is thread-safe.
  bool try_lock() noexcept {
    return enif_rwlock_tryrwlock(m_handle.get()) == 0;
  }

private:
  struct Deleter {
    void operator()(ErlNifRWLock *handle) const noexcept {
      enif_rwlock_destroy(handle);
    }
  };
  std::unique_ptr<ErlNifRWLock, Deleter> m_handle;
};
} // namespace fine

#endif
