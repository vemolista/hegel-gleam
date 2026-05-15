import argv
import envoy
import gleam/int
import gleam/json
import gleam/result
import gleam/string
import simplifile

pub fn get_test_cases() -> Int {
  case envoy.get("CONFORMANCE_TEST_CASES") {
    Ok(val) -> int.parse(val) |> result.unwrap(50)
    Error(Nil) -> 50
  }
}

pub fn get_params() -> String {
  case argv.load().arguments {
    [params] -> params
    _ -> panic as "Expected non-empty params"
  }
}

pub fn get_metrics_file() -> String {
  case envoy.get("CONFORMANCE_METRICS_FILE") {
    Ok(path) -> path
    Error(Nil) -> panic as "CONFORMANCE_METRICS_FILE not set"
  }
}

pub fn write_metrics(path: String, metrics: json.Json) {
  let json_string =
    json.to_string(metrics)
    |> string.replace("\u{85}", "\\u0085")
    |> string.replace("\u{2028}", "\\u2028")
    |> string.replace("\u{2029}", "\\u2029")
  let _ = simplifile.append(path, json_string <> "\n")
}
