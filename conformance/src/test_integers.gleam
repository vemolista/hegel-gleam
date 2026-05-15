import conformance
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import hegel
import hegel/generator/int_

pub type Params {
  Params(min_value: Option(Int), max_value: Option(Int))
}

fn params_decoder() -> decode.Decoder(Params) {
  use min_value <- decode.optional_field(
    "min_value",
    None,
    decode.optional(decode.int),
  )
  use max_value <- decode.optional_field(
    "max_value",
    None,
    decode.optional(decode.int),
  )
  decode.success(Params(min_value:, max_value:))
}

pub fn main() {
  let test_cases = conformance.get_test_cases()
  let metrics_file = conformance.get_metrics_file()
  let params_json = conformance.get_params()
  let params = case json.parse(params_json, params_decoder()) {
    Ok(p) -> p
    Error(_) -> panic as "Failed to parse integer params"
  }

  let gen = int_.new()
  let gen = case params.min_value {
    Some(min) -> gen |> int_.min(min)
    None -> gen
  }
  let gen = case params.max_value {
    Some(max) -> gen |> int_.max(max)
    None -> gen
  }
  let gen = int_.build(gen)

  hegel.run(hegel.Settings(test_cases: test_cases), fn(tc) {
    let value = tc |> hegel.draw(gen)
    let metrics = json.object([#("value", json.int(value))])
    let _ = conformance.write_metrics(metrics_file, metrics)

    Nil
  })
}
