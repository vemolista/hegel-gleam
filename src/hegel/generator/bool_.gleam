import gbor
import gleam/bool
import hegel/internal/case_worker
import hegel/internal/cbor
import hegel/internal/generator/core

pub fn generator() -> core.Generator(Bool) {
  core.from_basic(core.BasicGenerator(
    schema: cbor.cbor_map([#("type", gbor.CBString("boolean"))]),
    parse_raw: fn(cbor) {
      case cbor {
        gbor.CBBool(v) -> v
        _ -> case_worker.internal_panic("could not parse bool value")
      }
    },
    display: bool.to_string,
  ))
}
