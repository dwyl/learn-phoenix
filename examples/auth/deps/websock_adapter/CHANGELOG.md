## 0.5.8 (12 Nov 2024)

### Enhancements

* Improve handling of crashes during WebSock.init/1 calls (#20)

## 0.5.7 (9 Aug 2024)

### Enhancements

* Support use within Plug.Adapters.Test.Conn based tests

## 0.5.6 (25 Mar 2024)

### Enhancements

* Support Bandit 1.4+
* Minor mix packaging improvements

## 0.5.5 (30 Oct 2023)

### Enhancements

* Add a `:max_heap_size` option (#15, thanks @v0idpwn!)
* Validate client upgrade request at the time of upgrade (#14)

## 0.5.4 (15 Aug 2023)

### Enhancements

* Add ability to send preamble frames when closing a connection (#13)
* Improve test coverage (#12)

## 0.5.3 (15 Jun 2023)

### Enhancements

* Support draining signals as used by Phoenix (#10)

## 0.5.2 (15 Jun 2023)

### Changes

* Allow the sending of some extra options to Cowboy (#9)

### Fixes

* Allow terminate/2 to be optional for Cowboy adapter (#8)
* Allow nil detail reasons when closing connections in Cowboy

## 0.5.1 (24 Apr 2023)

### Changes

* Loosen optional dependency versioning on Bandit
* Add examples to documentation, correct minor typos

## 0.5.0 (13 Mar 2023)

### Enhancements

* Add support for `:stop` return tuple to specify explicit close code & detail message
