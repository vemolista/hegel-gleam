import conformance
import gleam/json
import hegel
import hegel/generator/bool_

pub fn main() {
  let test_cases = conformance.get_test_cases()
  let metrics_file = conformance.get_metrics_file()

  let gen = bool_.generator()

  hegel.run(hegel.Settings(test_cases: test_cases), fn(tc) {
    let value = tc |> hegel.draw(gen)
    let metrics = json.object([#("value", json.bool(value))])
    let _ = conformance.write_metrics(metrics_file, metrics)

    Nil
  })
}
