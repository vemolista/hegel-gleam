import gbor
import gleam/float
import gleam/option.{type Option, None, Some}
import hegel/internal/case_worker
import hegel/internal/cbor
import hegel/internal/generator/core

fn get_value(cbor: gbor.CBOR) -> Float {
  case cbor {
    gbor.CBFloat(value) -> value
    _ -> case_worker.internal_panic("expected float value")
  }
}

pub opaque type Builder {
  Builder(
    min: Option(Float),
    max: Option(Float),
    exclude_min: Bool,
    exclude_max: Bool,
  )
}

pub fn new() -> Builder {
  Builder(min: None, max: None, exclude_max: False, exclude_min: False)
}

pub fn min(builder: Builder, value: Float) -> Builder {
  Builder(..builder, min: Some(value))
}

pub fn max(builder: Builder, value: Float) -> Builder {
  Builder(..builder, max: Some(value))
}

pub fn exclude_min(builder: Builder) -> Builder {
  Builder(..builder, exclude_min: True)
}

pub fn exclude_max(builder: Builder) -> Builder {
  Builder(..builder, exclude_max: True)
}

pub fn build(builder: Builder) -> core.Generator(Float) {
  case builder.min, builder.max {
    Some(min), Some(max) if max <. min -> {
      panic as "Max must be higher than min"
    }
    _, _ -> {
      core.from_basic(core.BasicGenerator(
        schema: build_schema(builder),
        parse_raw: get_value,
        display: float.to_string,
      ))
    }
  }
}

fn build_schema(builder: Builder) -> gbor.CBOR {
  let schema =
    cbor.cbor_map([
      #("type", gbor.CBString("float")),
      #("allow_infinity", gbor.CBBool(False)),
      #("allow_nan", gbor.CBBool(False)),
    ])

  let schema = case builder.min {
    Some(min) -> cbor.cbor_map_insert(schema, "min_value", gbor.CBFloat(min))
    _ -> schema
  }

  let schema = case builder.max {
    Some(max) -> cbor.cbor_map_insert(schema, "max_value", gbor.CBFloat(max))
    _ -> schema
  }

  let schema = case builder.exclude_min {
    True ->
      cbor.cbor_map_insert(
        schema,
        "exclude_min",
        gbor.CBBool(builder.exclude_min),
      )
    False -> schema
  }

  let schema = case builder.exclude_max {
    True ->
      cbor.cbor_map_insert(
        schema,
        "exclude_max",
        gbor.CBBool(builder.exclude_max),
      )
    False -> schema
  }

  schema
}
