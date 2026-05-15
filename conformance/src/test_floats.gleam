import conformance
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import hegel
import hegel/generator/float_

pub type Params {
  Params(
    min_value: Option(Float),
    max_value: Option(Float),
    exclude_min: Option(Bool),
    exclude_max: Option(Bool),
  )
}

fn params_decoder() -> decode.Decoder(Params) {
  use min_value <- decode.optional_field(
    "min_value",
    None,
    decode.optional(decode.float),
  )
  use max_value <- decode.optional_field(
    "max_value",
    None,
    decode.optional(decode.float),
  )
  use exclude_min <- decode.optional_field(
    "exclude_min",
    None,
    decode.optional(decode.bool),
  )
  use exclude_max <- decode.optional_field(
    "exclude_max",
    None,
    decode.optional(decode.bool),
  )
  decode.success(Params(min_value:, max_value:, exclude_min:, exclude_max:))
}

pub fn main() {
  let test_cases = conformance.get_test_cases()
  let metrics_file = conformance.get_metrics_file()
  let params_json = conformance.get_params()
  let params = case json.parse(params_json, params_decoder()) {
    Ok(p) -> p
    Error(_) -> panic as "Failed to parse float params"
  }

  let gen = float_.new()
  let gen = case params.min_value {
    Some(min) -> gen |> float_.min(min)
    None -> gen
  }
  let gen = case params.max_value {
    Some(max) -> gen |> float_.max(max)
    None -> gen
  }
  let gen = case params.exclude_min {
    Some(True) -> gen |> float_.exclude_min()
    _ -> gen
  }
  let gen = case params.exclude_max {
    Some(True) -> gen |> float_.exclude_max()
    _ -> gen
  }
  let gen = float_.build(gen)

  hegel.run(hegel.Settings(test_cases: test_cases), fn(tc) {
    let value = tc |> hegel.draw(gen)
    let metrics = json.object([#("value", json.float(value))])
    let _ = conformance.write_metrics(metrics_file, metrics)

    Nil
  })
}
