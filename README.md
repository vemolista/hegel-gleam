# hegel-gleam

A property-based testing library for Gleam. Backed by Hypothesis, using the Hegel protocol.

> [!WARNING]
> Work in progress. Expect breaking changes, rough edges and incomplete feature set.

<!-- [![Package Version](https://img.shields.io/hexpm/v/hegel)](https://hex.pm/packages/hegel) -->
<!-- [![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/hegel/) -->

<!-- ```sh -->
<!-- gleam add hegel@1 -->
<!-- ``` -->

<!-- ```gleam -->
<!-- import hegel -->

<!-- pub fn main() -> Nil { -->
<!-- // TODO: An example of the project in use -->
<!-- } -->
<!-- ``` -->

<!-- Further documentation can be found at <https://hexdocs.pm/hegel>. -->

<!-- ## Development -->

<!-- ```sh -->
<!-- gleam run   # Run the project -->
<!-- gleam test  # Run the tests -->
<!-- ``` -->

## todo

- conformance/ package seems ugly to have in the root of another package, perhaps it should be somewhere else? However, placing it in hegel/src/ would mean shipping the conformance scripts with the library, which is ugly. We could place it in hegel/test/conformance, but then we have a gleam package inside another gleam package's test with a dependency on the package - yikes?
- ./src/hegel/generator/integer.gleam has some encoding stuff that should most likely be in ./src/hegel/internal/cbor.gleam
- use sceall instead of rolling own ffi for ports - have to figure out how to transfer ownership of the port
- get rid of internal panics
- improve output error messages and test them with birdie

## todo generators

- text
- characters
- dict
- list
- tuple
- email
- url
- domain
- ip_address
- date, time, datetime - work with gleam_time
- regex - look at gleam_regexp
- binary
- optional
- combinators
  - map
  - flatmap
  - oneof
  - filter
- something like hypothesis from? is it even possible?

done

- ints
- bools
- floats - conformance pending https://github.com/hegeldev/hegel-core/pull/128

## next

- text generators
