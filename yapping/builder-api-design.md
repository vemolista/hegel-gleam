# Builder API Design

This document describes the proposed builder-based API for hegel's generator
modules. It is the alternative to the config-record API sketched in
`ramblings/generator-api-implementation-plan.md`. The motivation is to keep an
idiomatic chained-builder feel for each generator kind while still letting
combinators (`map`, `flat_map`, `filter`, `one_of`, ...) operate on a single
uniform `Generator(a)` type.

## Goals

- Each generator kind exposes a small, kind-specific builder with chainable
  setters.
- Builder methods only exist where they make sense (no `integer.min` accidentally
  applied to a list).
- A terminal `build` step converts a builder into the uniform `Generator(a)`
  type used by `hegel.draw` and combinators.
- Stdlib name clashes (`list`, `dict`, `string`) are avoided by suffixing module
  names with `_`.

## Why builders, not config records

The config-record API requires the public facade module to own large `IntConfig`
/ `FloatConfig` / `TextConfig` records, because Gleam type aliases do not
re-export custom type constructors. Per-module builders avoid that. They mirror
the Rust reference implementation's split between `IntegerGenerator<T>` (the
builder) and `impl Generator<T>` (the trait), with one important difference:
Gleam has no traits, so the conversion from builder to `Generator(a)` is an
explicit `build` call rather than implicit trait dispatch.

The cost is one extra call per pipeline (`|> int_.build`). The benefit is
that builders keep the type-safety guarantee that kind-specific setters cannot
be applied to the wrong kind, and the public combinator surface stays small
because all combinators operate on `Generator(a)`.

## Layout

```diagram
╭─────────────────────────────────────────────╮
│ src/hegel/generator.gleam                  │
│ - opaque type Generator(a)                  │
│ - draw, map, flat_map, filter               │
│ - one_of, just, sampled_from, optional      │
╰─────────────────────┬───────────────────────╯
                      │ used by
                      ▼
╭─────────────────────────────────────────────╮
│ src/hegel/generator/                       │
│   bool_.gleam                            │
│   int_.gleam                             │
│   float_.gleam                           │
│   text_.gleam                            │
│   binary_.gleam                          │
│   list_.gleam                            │
│   dict_.gleam                            │
│   tuple_.gleam                           │
│ - opaque Builder(...) per kind              │
│ - new(), kind-specific setters              │
│ - build(builder) -> Generator(a)            │
╰─────────────────────┬───────────────────────╯
                      │ uses
                      ▼
╭─────────────────────────────────────────────╮
│ src/hegel/internal/generator/core.gleam    │
│ - opaque core, basic schema constructors    │
╰─────────────────────────────────────────────╯
```

## Naming convention

Each kind module is suffixed with `_` to avoid clashes with the Gleam
standard library. The names mirror the kind, not the underlying Gleam type, so
that protocol terminology stays close:

| Module    | Generates               |
| --------- | ----------------------- |
| `bool_`   | `Bool`                  |
| `int_`    | `Int`                   |
| `float_`  | `Float`                 |
| `text_`   | `String` (text)         |
| `binary_` | `BitArray`              |
| `list_`   | `List(a)`               |
| `dict_`   | `Dict(k, v)`            |
| `tuple_`  | `#(a, b)` ... `#(a..e)` |

Users import without aliasing:

```gleam
import hegel
import hegel/generator
import hegel/generator/int_
import hegel/generator/list_
```

## Per-kind module shape

Every kind module follows the same conventions:

- One opaque `Builder` type holding kind-specific config fields.
- `new(...)` constructor with required arguments only (e.g. `list_.new`
  takes the element generator; `int_.new` takes nothing).
- One setter per optional field, returning `Builder` for piping.
- One terminal `build(builder) -> Generator(a)` that validates and produces a
  `Generator(a)`.

### `int_`

```gleam
import gleam/option.{type Option, None, Some}
import hegel/generator.{type Generator}
import hegel/internal/generator/core

pub opaque type Builder {
  Builder(min: Option(Int), max: Option(Int))
}

pub fn new() -> Builder {
  Builder(min: None, max: None)
}

pub fn min(builder: Builder, value: Int) -> Builder {
  Builder(..builder, min: Some(value))
}

pub fn max(builder: Builder, value: Int) -> Builder {
  Builder(..builder, max: Some(value))
}

pub fn build(builder: Builder) -> Generator(Int) {
  // validate min <= max, build CBOR schema, return basic Generator(Int)
  core.basic_int(builder.min, builder.max)
}
```

### `float_`

```gleam
pub opaque type Builder {
  Builder(
    min: Option(Float),
    max: Option(Float),
    exclude_min: Bool,
    exclude_max: Bool,
    allow_nan: Option(Bool),
    allow_infinity: Option(Bool),
  )
}

pub fn new() -> Builder
pub fn min(builder: Builder, value: Float) -> Builder
pub fn max(builder: Builder, value: Float) -> Builder
pub fn exclude_min(builder: Builder, value: Bool) -> Builder
pub fn exclude_max(builder: Builder, value: Bool) -> Builder
pub fn allow_nan(builder: Builder, value: Bool) -> Builder
pub fn allow_infinity(builder: Builder, value: Bool) -> Builder
pub fn build(builder: Builder) -> Generator(Float)
```

### `text_`

```gleam
pub opaque type Builder {
  Builder(
    min_size: Option(Int),
    max_size: Option(Int),
    categories: Option(List(Category)),
    exclude_categories: Option(List(Category)),
  )
}

pub fn new() -> Builder
pub fn min_size(builder: Builder, n: Int) -> Builder
pub fn max_size(builder: Builder, n: Int) -> Builder
pub fn categories(builder: Builder, cs: List(Category)) -> Builder
pub fn exclude_categories(builder: Builder, cs: List(Category)) -> Builder
pub fn build(builder: Builder) -> Generator(String)
```

`text_.build` validates that `categories` and `exclude_categories` are not
both set. See the appendix for a phantom-typed alternative that catches that
conflict at compile time.

### `list_`

```gleam
pub opaque type Builder(a) {
  Builder(
    element: Generator(a),
    min_size: Option(Int),
    max_size: Option(Int),
    unique: Bool,
  )
}

pub fn new(element: Generator(a)) -> Builder(a)
pub fn min_size(builder: Builder(a), n: Int) -> Builder(a)
pub fn max_size(builder: Builder(a), n: Int) -> Builder(a)
pub fn unique(builder: Builder(a), value: Bool) -> Builder(a)
pub fn build(builder: Builder(a)) -> Generator(List(a))
```

### `dict_`

```gleam
pub opaque type Builder(k, v) {
  Builder(
    keys: Generator(k),
    values: Generator(v),
    min_size: Option(Int),
    max_size: Option(Int),
  )
}

pub fn new(keys: Generator(k), values: Generator(v)) -> Builder(k, v)
pub fn min_size(builder: Builder(k, v), n: Int) -> Builder(k, v)
pub fn max_size(builder: Builder(k, v), n: Int) -> Builder(k, v)
pub fn build(builder: Builder(k, v)) -> Generator(Dict(k, v))
```

### `tuple_`

Tuples have no per-element config beyond the children, so there is no builder.
The module exposes plain constructors:

```gleam
pub fn new2(a: Generator(a), b: Generator(b)) -> Generator(#(a, b))
pub fn new3(a, b, c) -> Generator(#(a, b, c))
pub fn new4(a, b, c, d) -> Generator(#(a, b, c, d))
pub fn new5(a, b, c, d, e) -> Generator(#(a, b, c, d, e))
```

### `bool_` and `binary_`

`bool_` likewise needs no builder:

```gleam
pub fn new() -> Generator(Bool)
```

`binary_` follows the same shape as `text_` for size limits but without
character categories:

```gleam
pub opaque type Builder
pub fn new() -> Builder
pub fn min_size(builder: Builder, n: Int) -> Builder
pub fn max_size(builder: Builder, n: Int) -> Builder
pub fn build(builder: Builder) -> Generator(BitArray)
```

## Combinators

Combinators live in `hegel/generator` and operate on the uniform
`Generator(a)`. They never know about builder types.

```gleam
pub fn map(gen: Generator(a), f: fn(a) -> b) -> Generator(b)
pub fn flat_map(gen: Generator(a), f: fn(a) -> Generator(b)) -> Generator(b)
pub fn filter(gen: Generator(a), predicate: fn(a) -> Bool) -> Generator(a)
pub fn one_of(generators: List(Generator(a))) -> Generator(a)
pub fn just(value: a) -> Generator(a)
pub fn sampled_from(options: List(a)) -> Generator(a)
pub fn optional(element: Generator(a)) -> Generator(Option(a))
```

## Usage examples

### Simple draws

```gleam
import hegel
import hegel/generator/bool_
import hegel/generator/int_

pub fn example(tc) {
  let b = hegel.draw(tc, bool_.new())
  let n = hegel.draw(tc, int_.new() |> int_.build)
  Nil
}
```

### Bounded primitives

```gleam
import hegel
import hegel/generator/float_
import hegel/generator/int_

pub fn example(tc) {
  let i =
    hegel.draw(
      tc,
      int_.new() |> int_.min(1) |> int_.max(100) |> int_.build,
    )

  let f =
    hegel.draw(
      tc,
      float_.new()
        |> float_.min(0.0)
        |> float_.max(1.0)
        |> float_.exclude_max(True)
        |> float_.build,
    )
  Nil
}
```

### Configured collections

```gleam
import hegel
import hegel/generator/int_
import hegel/generator/list_

pub fn example(tc) {
  let element = int_.new() |> int_.min(0) |> int_.max(99) |> int_.build

  let xs =
    hegel.draw(
      tc,
      list_.new(element)
        |> list_.min_size(1)
        |> list_.max_size(10)
        |> list_.unique(True)
        |> list_.build,
    )
  Nil
}
```

### Composition with combinators

```gleam
import hegel
import hegel/generator
import hegel/generator/int_
import hegel/generator/text_

pub fn example(tc) {
  let positive =
    int_.new()
    |> int_.min(0)
    |> int_.build
    |> generator.map(fn(x) { x + 1 })

  let small_text =
    text_.new()
    |> text_.min_size(1)
    |> text_.max_size(8)
    |> text_.build

  let label =
    hegel.draw(tc, generator.one_of([small_text, generator.just("default")]))

  Nil
}
```

### Tuples

```gleam
import hegel
import hegel/generator/int_
import hegel/generator/text_
import hegel/generator/tuple_

pub fn example(tc) {
  let pair =
    tuple_.new2(
      int_.new() |> int_.build,
      text_.new() |> text_.build,
    )

  let #(n, s) = hegel.draw(tc, pair)
  Nil
}
```

## Validation strategy

Validation lives inside each kind's `build` function. It runs once when the
builder is materialized into a `Generator(a)`, before any protocol traffic.

Examples of runtime checks:

- `int_.build`: `min <= max` when both are set.
- `float_.build`: `min <= max`; `allow_nan = True` forbids any bound;
  `allow_infinity = True` with both bounds set is forbidden.
- `text_.build`: `min_size <= max_size`; `categories` and
  `exclude_categories` are not both set.
- `list_.build` / `dict_.build`: `min_size <= max_size`.

For value-level constraints (e.g. `min <= max`) the check must stay at runtime;
phantom types cannot inspect values. For categorical constraints (e.g. mutually
exclusive flags) phantom types are an option — see the appendix.

## Tradeoffs

- **Pro:** Idiomatic Gleam pipelines.
- **Pro:** Setters are statically scoped to the right kind.
- **Pro:** No giant config records polluting the public facade.
- **Pro:** Combinators stay small and operate uniformly on `Generator(a)`.
- **Con:** One extra call per pipeline (`|> int_.build`).
- **Con:** Multiple imports per file when mixing kinds.
- **Neutral:** Inner generators in `list_.new(...)` need an explicit `build`
  before being passed in. The config-record alternative has the same nesting
  cost, just spelled differently.

## File-level change plan

| Path                                                  | Action                                                                                      |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `src/hegel/internal/generator/core.gleam`            | Replace stubs with real opaque generator core, basic constructors, draw logic.              |
| `src/hegel/generator.gleam`                          | New facade module with `Generator(a)`, `draw`, combinators.                                 |
| `src/hegel/generator/bool_.gleam`                    | New module: `new() -> Generator(Bool)`.                                                     |
| `src/hegel/generator/int_.gleam`                     | New module: `Builder`, `new`, `min`, `max`, `build`.                                        |
| `src/hegel/generator/float_.gleam`                   | New module: `Builder`, `new`, `min`, `max`, `exclude_min`, `exclude_max`, `allow_nan`, etc. |
| `src/hegel/generator/text_.gleam`                    | New module: `Builder`, sizing, categories, `build`.                                         |
| `src/hegel/generator/binary_.gleam`                  | New module: `Builder`, sizing, `build`.                                                     |
| `src/hegel/generator/list_.gleam`                    | New module: `Builder(a)`, sizing, unique, `build`.                                          |
| `src/hegel/generator/dict_.gleam`                    | New module: `Builder(k, v)`, sizing, `build`.                                               |
| `src/hegel/generator/tuple_.gleam`                   | New module: `new2`..`new5`.                                                                 |
| `src/hegel/generator/{bool,integer,float,...}.gleam` | Delete; migrate tests in the same change set.                                               |
| `src/hegel.gleam`                                    | Re-export `draw` from `hegel/generator`.                                                   |
| `test/hegel/*_test.gleam`                            | Migrate imports and call sites.                                                             |

## Testing strategy

1. After core implementation: `gleam build`.
2. After each kind module: focused tests via `gleam test`.
3. After facade migration: `gleam format`, `gleam build`, `gleam test`.
4. After validation: add unit-style tests using `exception.rescue` for invalid
   builder configurations.
5. After combinators: focused tests for each combinator and nested combinations.

## Rollout order

1. `hegel/internal/generator/core.gleam` — opaque core, basic constructors.
2. `hegel/generator.gleam` — facade with `Generator(a)` and `draw`.
3. `bool_`, `int_`, `float_` — primitives.
4. `text_`, `binary_` — text and binary.
5. `list_`, `dict_`, `tuple_` — collections.
6. Delete legacy `bool/integer/float/string/list/dict/tuple` modules and migrate
   tests.
7. Combinators in `hegel/generator`: `map`, `just`, `sampled_from`, `optional`,
   `one_of`.
8. Span/collection protocol helpers (per `ramblings/spans.md`).
9. `flat_map`, `filter`, non-basic collection fallback.

## Appendix: Phantom types for `text_`

The `categories` and `exclude_categories` fields on `text_.Builder` are
mutually exclusive. The default plan is to validate this at runtime in `build`.
A nicer alternative is to encode the conflict in the type system using the
type-state pattern from `docs/phantom-types-post.md`, so the compiler rejects
the combination directly.

```gleam
// src/hegel/generator/text_.gleam

// Phantom states for character configuration
pub opaque type CharsUnset { CharsUnset }
pub opaque type CharsIncluded { CharsIncluded }
pub opaque type CharsExcluded { CharsExcluded }

pub opaque type Builder(chars) {
  Builder(
    min_size: Option(Int),
    max_size: Option(Int),
    include: Option(List(Category)),
    exclude: Option(List(Category)),
  )
}

pub fn new() -> Builder(CharsUnset) {
  Builder(min_size: None, max_size: None, include: None, exclude: None)
}

// Sizing works in any state — the phantom variable stays polymorphic
pub fn min_size(b: Builder(c), n: Int) -> Builder(c) {
  Builder(..b, min_size: Some(n))
}

pub fn max_size(b: Builder(c), n: Int) -> Builder(c) {
  Builder(..b, max_size: Some(n))
}

// Transitions: only callable from the unset state
pub fn categories(b: Builder(CharsUnset), cs: List(Category)) -> Builder(CharsIncluded) {
  Builder(..b, include: Some(cs))
}

pub fn exclude_categories(b: Builder(CharsUnset), cs: List(Category)) -> Builder(CharsExcluded) {
  Builder(..b, exclude: Some(cs))
}

// Build accepts any state
pub fn build(b: Builder(c)) -> Generator(String) { ... }
```

This compiles:

```gleam
text_.new() |> text_.min_size(1) |> text_.categories([Alpha]) |> text_.build
text_.new() |> text_.exclude_categories([Whitespace]) |> text_.build
```

This is a compile error:

```gleam
text_.new()
|> text_.categories([Alpha])
|> text_.exclude_categories([Whitespace])  // expects Builder(CharsUnset), got Builder(CharsIncluded)
|> text_.build
```

Cost: three extra opaque types and one type parameter on `Builder`. Benefit: the
mutual-exclusion rule is enforced by the compiler, not by a runtime panic in
`build`. This is the only kind module where the cost/benefit clearly favors
phantom types — every other validation rule in the generator surface is a
value-level constraint (`min <= max`, `min_size <= max_size`) that phantom
types cannot express without dependent types.
