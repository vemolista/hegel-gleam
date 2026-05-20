# API v1 — Flat module with convenience + builder

All generators live in a single `hegel` module. No sub-modules. Convenience functions cover the 80% case; opaque builders cover the remaining 20%.

## Principles

- **Flat module.** Everything is in `hegel`. No `hegel/generator/int_`, no `hegel/generator/float_`. One import.
- **Convenience first.** `int()`, `float()`, `float_range(min, max)` cover the common cases.
- **Opaque builders for power use.** `float_new() |> float_min(1.0) |> float_max(10.0) |> float_exclude_min |> float_build` when you need the knobs.
- **Prefixed functions.** Since everything shares one module, every generator-specific function is prefixed: `float_new`, `float_min`, `int_new`, `int_min`, etc.
- **No separate generator modules.** The `hegel/generator/*` modules are internal implementation only.

## Generator type

```gleam
pub opaque type Generator(a)
```

One uniform type. Combinators and `draw` operate on it. Builders produce it.

## Primitive generators

### `bool`

No builder needed — nothing to configure.

```gleam
bool() -> Generator(Bool)
```

### `int`

Convenience:

```gleam
int()                              -> Generator(Int)
int_range(min: Int, max: Int)      -> Generator(Int) // When min > max, swap them so we do not return an error.
```



### `float`

Convenience:

```gleam
float()                                -> Generator(Float)
float_range(min: Float, max: Float)    -> Generator(Float) // When min > max, swap them so we do not return an error.
```

Builder:

```gleam
float_new()                                    -> FloatBuilder
float_min(builder: FloatBuilder, value: Float) -> FloatBuilder // When min > max, swap them so we do not return an error.
float_max(builder: FloatBuilder, value: Float) -> FloatBuilder // When min > max, swap them so we do not return an error.
float_exclude_min(builder: FloatBuilder)        -> FloatBuilder
float_exclude_max(builder: FloatBuilder)        -> FloatBuilder
float_build(builder: FloatBuilder)              -> Generator(Float)
```

Infinity and NaN are not supported in Gleam.

Protocol fields: `min_value`, `max_value`, `exclude_min`, `exclude_max`.

`exclude_min`/`exclude_max` are simple toggles (no Bool argument — they only turn on). This matches the protocol default of `false` and the fact that you'd never want to un-exclude after excluding in a pipeline.

### `text` (protocol: "string" schema)

Convenience:

```gleam
text()                              -> Generator(String)
text_range(min: Int, max: Int)      -> Generator(String) // When min > max, swap them so we do not return an error.
```

Builder:

```gleam
text_new()                                                        -> StringBuilder
text_min_size(builder: StringBuilder, n: Int)                     -> StringBuilder
text_max_size(builder: StringBuilder, n: Int)                     -> StringBuilder
text_min_codepoint(builder: StringBuilder, n: Int)                -> StringBuilder
text_max_codepoint(builder: StringBuilder, n: Int)                -> StringBuilder
text_categories(builder: StringBuilder, cs: List(String))         -> StringBuilder
text_exclude_categories(builder: StringBuilder, cs: List(String)) -> StringBuilder
text_include_characters(builder: StringBuilder, chars: String)    -> StringBuilder
text_exclude_characters(builder: StringBuilder, chars: String)    -> StringBuilder
text_codec(builder: StringBuilder, codec: String)                 -> StringBuilder
text_build(builder: StringBuilder)                                -> Generator(String)
```

Protocol fields: `min_size`, `max_size`, `min_codepoint`, `max_codepoint`, `categories`, `exclude_categories`, `include_characters`, `exclude_characters`, `codec`.

Validation in `string_build`:
- `min_size <= max_size`.
- `categories` and `exclude_categories` not both set. <-- could be handled with a phantom type instead, would give a compile time, instead of a runtime error
- No overlap between `include_characters` and `exclude_characters`.

### `characters`

Same as `text`, but length 1.

### `binary` (protocol: "binary" schema)

Convenience:

```gleam
bit_array()                               -> Generator(BitArray)
bit_array_range(min: Int, max: Int)       -> Generator(BitArray) // When min > max, swap them so we do not return an error.
```

## Collection generators

### `list`

Convenience:

```gleam
list(elements: Generator(a))                              -> Generator(List(a))
list_bounded(elements: Generator(a), min: Int, max: Int)  -> Generator(List(a))
// Potentially - list_non_empty(elements: Generator(a))
```

Builder:

```gleam
list_new(elements: Generator(a))                          -> ListBuilder(a)
list_min_size(builder: ListBuilder(a), n: Int)           -> ListBuilder(a)
list_max_size(builder: ListBuilder(a), n: Int)           -> ListBuilder(a)
list_unique(builder: ListBuilder(a))                      -> ListBuilder(a)
list_build(builder: ListBuilder(a))                       -> Generator(List(a))
```

`list_unique` is a toggle like `float_exclude_min` — turns on uniqueness, no Bool arg.

Protocol fields: `elements`, `min_size`, `max_size`, `unique`.

### `dict`

Convenience:

```gleam
dict(keys: Generator(k), values: Generator(v))                        -> Generator(Dict(k, v))
dict_bounded(keys: Generator(k), values: Generator(v), min: Int, max: Int) -> Generator(Dict(k, v))
```

### `tuple`

No builder — just fixed-arity constructors:

```gleam
tuple2(a: Generator(a), b: Generator(b))              -> Generator(#(a, b))
tuple3(a, b, c)                                       -> Generator(#(a, b, c))
tuple4(a, b, c, d)                                    -> Generator(#(a, b, c, d))
tuple5(a, b, c, d, e)                                 -> Generator(#(a, b, c, d, e))
```

## Special generators

### `regex`

```gleam
regex(pattern: String)                                -> Generator(String)
```

Protocol fields: `pattern`, `fullmatch`, `alphabet` (defaults to `{"codec": "utf-8"}`).

May want a builder later for `fullmatch` and alphabet config, but `regex(pattern)` covers the main case.

### Domain-specific

These have no configurable fields (or very few), so no builders:

```gleam
email()                               -> Generator(String)
url()                                 -> Generator(String)
domain()                              -> Generator(String)
ip_address(version: IpAddressVersion) -> Generator(String)    // version: 4 or 6
date()                                -> Generator(String)
time()                                -> Generator(String)
datetime()                            -> Generator(String)
```

`domain` has an optional `max_length` — could add `domain_max_length` later or a small builder if needed.

## Combinators

Operate on `Generator(a)` only. No builder involvement.

```gleam
map(gen: Generator(a), f: fn(a) -> b)                 -> Generator(b)
flat_map(gen: Generator(a), f: fn(a) -> Generator(b)) -> Generator(b)
filter(gen: Generator(a), predicate: fn(a) -> Bool)   -> Generator(a)
one_of(generators: List(Generator(a)))                -> Generator(a)
just(value: a)                                        -> Generator(a)
sampled_from(options: List(a))                        -> Generator(a)
optional(element: Generator(a))                       -> Generator(Option(a))
```

## Test API

```gleam
pub type Settings {
  Settings(test_cases: Int)
}

pub fn default_settings() -> Settings
pub fn run(settings: Settings, body: fn(TestCase) -> Nil) -> Nil
pub fn given(body: fn(TestCase) -> Nil) -> Nil
pub fn draw(tc: TestCase, gen: Generator(a)) -> a
```

## Usage examples

### Simple

```gleam
import hegel

pub fn example(tc: hegel.TestCase) {
  let b = hegel.draw(tc, hegel.bool())
  let n = hegel.draw(tc, hegel.int())
  let f = hegel.draw(tc, hegel.float())
  Nil
}
```

### Bounded primitives

```gleam
import hegel

pub fn example(tc: hegel.TestCase) {
  let i = hegel.draw(tc, hegel.int_range(1, 100))
  let f = hegel.draw(tc, hegel.float_range(0.0, 1.0))
  Nil
}
```

### Builder — exclude min/max

```gleam
import hegel

pub fn example(tc: hegel.TestCase) {
  let f =
    hegel.draw(
      tc,
      hegel.float_new()
        |> hegel.float_min(0.0)
        |> hegel.float_max(1.0)
        |> hegel.float_exclude_min
        |> hegel.float_exclude_max
        |> hegel.float_build,
    )
  Nil
}
```

### Collections

```gleam
import hegel

pub fn example(tc: hegel.TestCase) {
  let xs = hegel.draw(tc, hegel.list(hegel.int()))
  let ys = hegel.draw(tc, hegel.list_bounded(hegel.int(), 1, 10))

  let unique_ys =
    hegel.draw(
      tc,
      hegel.list_new(hegel.int())
        |> hegel.list_min_size(1)
        |> hegel.list_max_size(10)
        |> hegel.list_unique
        |> hegel.list_build,
    )
  Nil
}
```

### Composition

```gleam
import hegel

pub fn example(tc: hegel.TestCase) {
  let positive =
    hegel.int_new()
    |> hegel.int_min(0)
    |> hegel.int_build
    |> hegel.map(fn(x) { x + 1 })

  let label =
    hegel.draw(
      tc,
      hegel.one_of([
        hegel.string_range(1, 8),
        hegel.just("default"),
      ]),
    )
  Nil
}
```

## Naming convention

| Generates       | Convenience          | Builder constructor | Builder type     |
| --------------- | -------------------- | ------------------- | ---------------- |
| `Bool`          | `bool()`             | —                   | —                |
| `Int`           | `int()`, `int_range` | `int_new()`         | `IntBuilder`     |
| `Float`         | `float()`, `float_range` | `float_new()`   | `FloatBuilder`   |
| `String`        | `string()`, `string_range` | `string_new()` | `StringBuilder` |
| `BitArray`      | `bit_array()`, `bit_array_range` | `binary_new()` | `BinaryBuilder` |
| `List(a)`       | `list()`, `list_bounded` | `list_new()`   | `ListBuilder(a)` |
| `Dict(k, v)`    | `dict()`, `dict_bounded` | `dict_new()`  | `DictBuilder(k,v)` |

All builder setters and `build` are prefixed: `float_min`, `float_max`, `float_build`, `int_min`, `int_build`, etc.

All builder types are opaque.

## Toggles vs Bool arguments

Functions like `float_exclude_min`, `float_exclude_max`, `list_unique` take no argument — they switch a field from its protocol default (`false`) to `true`. Rationale:

- You never need to un-set them in a pipeline.
- Fewer keystrokes, reads more naturally.
- If a user needs the non-default, they use the builder; if they don't, they use the convenience function.

## Validation

All validation happens in `build`. Runtime checks before any protocol traffic:

- `int_build`: `min <= max`.
- `float_build`: `min <= max`; `allow_nan` with bounds is invalid; `allow_infinity` with both bounds is invalid.
- `string_build`: `min_size <= max_size`; `categories` and `exclude_categories` not both set; no overlap between `include_characters` and `exclude_characters`.
- `list_build` / `dict_build`: `min_size <= max_size`.

Invalid configurations cause a runtime error with a descriptive message.

## Internal layout

The public `hegel` module re-exports everything. Internally, generator logic stays in `src/hegel/generator/` for code organization — but users never import from there.

```diagram
╭───────────────────────────────────────────────╮
│ src/hegel.gleam                               │
│ - re-exports all public API                    │
│ - Settings, run, given, draw                   │
│ - all convenience functions                    │
│ - all builder types (opaque) and methods       │
│ - all combinators                              │
╰───────────────────────┬───────────────────────╯
                        │ delegates to
                        ▼
╭───────────────────────────────────────────────╮
│ src/hegel/generator/                          │
│   bool_.gleam, int_.gleam, float_.gleam, ...   │
│ - internal builder + schema construction       │
│ - not imported by users                        │
╰───────────────────────┬───────────────────────╯
                        │ uses
                        ▼
╭───────────────────────────────────────────────╮
│ src/hegel/internal/generator/core.gleam       │
│ - opaque Generator(a) core                     │
│ - basic schema constructors                    │
╰───────────────────────────────────────────────╯
```
