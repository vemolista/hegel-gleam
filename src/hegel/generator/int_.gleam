import gbor
import gleam/bit_array
import gleam/int
import gleam/option.{type Option, None, Some}
import hegel/internal/case_worker
import hegel/internal/cbor
import hegel/internal/generator/core

fn bignum_from_bytes(bytes: BitArray) -> Int {
  let size = bit_array.byte_size(bytes)
  let assert <<value:unsigned-big-size(size)-unit(8)>> = bytes
  value
}

/// Compute the minimum number of bytes required to represent a non-negative
/// integer in big-endian. Returns 1 for 0.
fn byte_size_of(value: Int) -> Int {
  case value {
    0 -> 1
    _ -> byte_size_loop(value, 0)
  }
}

fn byte_size_loop(value: Int, acc: Int) -> Int {
  case value {
    0 -> acc
    _ -> byte_size_loop(int.bitwise_shift_right(value, 8), acc + 1)
  }
}

/// Convert a non-negative integer to its minimal big-endian byte
/// representation as a BitArray.
fn int_to_unsigned_bytes(value: Int) -> BitArray {
  let n = byte_size_of(value)
  <<value:big-size(n)-unit(8)>>
}

// 2^64 — the exclusive upper bound for CBOR's standard integer encoding.
const cbor_int_limit: Int = 0x10000000000000000

/// Convert a Gleam Int to a CBOR value. Values that exceed CBOR's 64-bit
/// integer range are encoded as CBOR bignums (tag 2 for positive, tag 3 for
/// negative) per RFC 8949. This works around gbor's encoder, which does not
/// emit bignum tags for large CBInt values.
fn int_to_cbor(value: Int) -> gbor.CBOR {
  case value {
    v if v >= 0 && v < cbor_int_limit -> gbor.CBInt(v)
    v if v >= cbor_int_limit ->
      gbor.CBTagged(2, gbor.CBBinary(int_to_unsigned_bytes(v)))
    v if v + cbor_int_limit >= 0 -> gbor.CBInt(v)
    v -> gbor.CBTagged(3, gbor.CBBinary(int_to_unsigned_bytes(-1 - v)))
  }
}

fn get_value(cbor: gbor.CBOR) -> Int {
  case cbor {
    gbor.CBInt(value) -> value
    gbor.CBTagged(2, gbor.CBBinary(bytes)) -> bignum_from_bytes(bytes)
    gbor.CBTagged(3, gbor.CBBinary(bytes)) -> -1 - bignum_from_bytes(bytes)
    _ -> case_worker.internal_panic("could not parse int value")
  }
}

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

pub type BuilderError {
  BuilderError(message: String)
}

pub fn build(builder: Builder) -> core.Generator(Int) {
  case builder.min, builder.max {
    Some(min), Some(max) if max < min -> {
      panic as "Max must be higher than min"
    }
    min, max -> {
      core.from_basic(core.BasicGenerator(
        schema: build_schema(min, max),
        parse_raw: get_value,
        display: int.to_string,
      ))
    }
  }
}

fn build_schema(min: Option(Int), max: Option(Int)) -> gbor.CBOR {
  let schema = cbor.cbor_map([#("type", gbor.CBString("integer"))])

  let schema = case min {
    Some(min) -> cbor.cbor_map_insert(schema, "min_value", int_to_cbor(min))
    _ -> schema
  }

  let schema = case max {
    Some(max) -> cbor.cbor_map_insert(schema, "max_value", int_to_cbor(max))
    _ -> schema
  }

  schema
}
